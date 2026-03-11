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

        Applebox.logger.debug("fetching default kernel")
        let kernel = try await ClientKernel.getDefaultKernel(for: .current)

        let uid = getuid()
        let userName = ProcessInfo.processInfo.userName
        let hostHome = ToolboxPaths.hostHomeDirectory.path
        let hostShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/sh"
        let containerHome = ToolboxPaths.containerHomeDirectory(userName: userName)
        let hostHomeInContainer = ToolboxPaths.containerMountPointForHostHome(userName: userName)

        let imageConfig = try await image.config(for: platform).config
        var environment = imageConfig?.env ?? []
        let toolboxOverrides: [(String, String)] = [
            ("HOME", containerHome),
            ("SHELL", hostShell),
            ("USER", userName),
            ("LANG", "C.UTF-8"),
            ("TERM", "xterm-256color"),
            ("APPLEBOX_UID", "\(uid)"),
            ("APPLEBOX_GUEST_GID", "1000"),
            ("APPLEBOX_CONTAINER_NAME", name),
            ("APPLEBOX_IMAGE", image.reference),
            ("XDG_RUNTIME_DIR", "/run/user/\(uid)"),
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

        let runDir = try ToolboxPaths.ensureHostRuntimeDirectory(for: name)

        Applebox.logger.debug(
            "configuring container", metadata: ["name": "\(name)", "runDir": "\(runDir.path)"])

        var config = ContainerConfiguration(id: name, image: image.description, process: initProcess)
        config.platform = platform
        config.useInit = true
        config.ssh = true
        config.resources = try Parser.resources(cpus: nil, memory: nil)

        config.labels = [
            ToolboxLabel.managed: "true"
        ]

        config.mounts = [
            .virtiofs(source: hostHome, destination: hostHomeInContainer, options: []),
            .virtiofs(
                source: runDir.path, destination: ToolboxPaths.containerRuntimeMountPoint,
                options: []),
        ]

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
        if case .running(_, let status) = builtin {
            Applebox.logger.debug("network status", metadata: ["ipv4Gateway": "\(status)"])
            config.dns = .init(nameservers: [status.ipv4Gateway.description])
        }

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
