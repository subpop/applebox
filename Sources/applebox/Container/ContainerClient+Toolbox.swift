// Copyright 2026 Link Dupont
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import ContainerAPIClient
import ContainerResource
import Containerization
import ContainerizationError
import ContainerizationOCI
import Foundation
import Logging

enum ToolboxLabel {
    static let managed = "dev.applebox.managed"
}

extension ContainerClient {
    func createToolbox(
        name: String,
        image: ClientImage,
    ) async throws {
        try Utility.validEntityName(name)

        let platform = Parser.platform(os: "linux", arch: Arch.hostArchitecture().rawValue)
        let kernel = try await ClientKernel.getDefaultKernel(for: .current)

        let uid = getuid()
        let userName = ProcessInfo.processInfo.userName
        let hostHome = ToolboxPaths.hostHomeDirectory.path
        let hostShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/sh"
        let containerHome = ToolboxPaths.containerHomeDirectory(userName: userName)

        // Customize environment with local values
        let imageConfig = try await image.config(for: platform).config
        var environment = imageConfig?.env ?? []
        let toolboxOverrides: [(String, String)] = [
            ("HOME", containerHome),
            ("SHELL", hostShell),
            ("USER", userName),
            ("LANG", ProcessInfo.processInfo.environment["LANG"] ?? "C.UTF-8"),
            ("TERM", ProcessInfo.processInfo.environment["TERM"] ?? "xterm-256color"),
            ("HOST_UID", "\(uid)"),
            ("APPLEBOX_CONTAINER_NAME", name),
            ("APPLEBOX_IMAGE", image.reference),
        ]
        for (key, value) in toolboxOverrides {
            environment.removeAll { $0.hasPrefix("\(key)=") }
            environment.append("\(key)=\(value)")
        }

        let initProcess = ProcessConfiguration(
            executable: "/bin/sh",
            arguments: ["-c", InitScript.source],
            environment: environment,
            workingDirectory: "/",
            terminal: false,
            user: .id(uid: 0, gid: 0),
        )

        // Get or create the container home volume
        let containerHomeVolume: Volume
        do {
            containerHomeVolume = try await ClientVolume.create(
                name: "\(name)-home",
                driver: "local",
                driverOpts: [:],
                labels: [ToolboxLabel.managed: "true"]
            )
        } catch let error as VolumeError {
            guard case .volumeAlreadyExists = error else {
                throw error
            }
            // Volume already exists, just inspect it
            containerHomeVolume = try await ClientVolume.inspect("\(name)-home")
        } catch let error as ContainerizationError {
            // Handle XPC-wrapped volumeAlreadyExists error
            guard error.message.contains("already exists") else {
                throw error
            }
            containerHomeVolume = try await ClientVolume.inspect("\(name)-home")
        }

        let runDir = try ToolboxPaths.ensureHostRuntimeDirectory(for: name)

        Applebox.logger.debug(
            "configuring container", metadata: ["name": "\(name)", "runDir": "\(runDir.path)"])

        var config = ContainerConfiguration(
            id: name, image: image.description, process: initProcess)
        config.platform = platform
        config.useInit = true
        config.ssh = true
        config.resources = try Parser.resources(cpus: nil, memory: nil)

        config.labels = [
            ToolboxLabel.managed: "true"
        ]

        // Set up mounts
        config.mounts = [
            .volume(
                name: containerHomeVolume.name, format: containerHomeVolume.format,
                source: containerHomeVolume.source, destination: "/home",
                options: []),
            .virtiofs(source: hostHome, destination: hostHome, options: []),
            .virtiofs(
                source: runDir.path, destination: ToolboxPaths.containerRuntimeMountPoint,
                options: []),
        ]

        // Set up networking
        guard let builtin = try await ClientNetwork.builtin else {
            throw AppleboxError.builtinNetworkNotPresent
        }
        Applebox.logger.debug("network state", metadata: ["network": "\(builtin)"])
        config.networks = [
            AttachmentConfiguration(
                network: builtin.id,
                options: AttachmentOptions(hostname: name, macAddress: nil),
            )
        ]
        // Use empty nameservers so the sandbox service dynamically resolves
        // the gateway IP from the allocated network attachment at every boot.
        // This prevents stale DNS when the host NAT subnet changes.
        config.dns = .init(nameservers: [])

        try await create(
            configuration: config,
            options: ContainerCreateOptions(autoRemove: false),
            kernel: kernel,
        )
        Applebox.logger.debug("container created and running", metadata: ["name": "\(name)"])
    }

    func ensureRunning(id: String) async throws -> ContainerSnapshot {
        var container = try await get(id: id)
        Applebox.logger.debug(
            "container status", metadata: ["id": "\(id)", "status": "\(container.status.rawValue)"])
        if container.status == .running {
            return container
        }
        if container.status == .stopped || container.status == .unknown {
            Applebox.logger.debug("starting stopped container", metadata: ["id": "\(id)"])
            let stampURL = ToolboxPaths.hostInitializedStampURL(for: id)
            try? FileManager.default.removeItem(at: stampURL)

            let stdio: [FileHandle?] = [nil, nil, nil]
            let process = try await bootstrap(id: id, stdio: stdio)
            try await process.start()
            container = try await get(id: id)
            guard container.status == .running else {
                throw AppleboxError.containerInvalidState(
                    "Container did not stay running after start. The init process may have exited. "
                        + "Recreate the container or use an image with a long-running entrypoint.",
                )
            }

            let deadline = ContinuousClock.now + .seconds(30)
            while ContinuousClock.now < deadline {
                if FileManager.default.fileExists(atPath: stampURL.path) {
                    Applebox.logger.debug("container initialized", metadata: ["id": "\(id)"])
                    return container
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw AppleboxError.initializationTimeout(id)
        }
        throw AppleboxError.containerInvalidState(
            "container \(id) in unexpected state: \(container.status)",
        )
    }
}
