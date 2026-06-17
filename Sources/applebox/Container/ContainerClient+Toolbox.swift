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
import ContainerPersistence
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
        let gid = getgid()
        let userName = ProcessInfo.processInfo.userName
        let hostHome = ToolboxPaths.hostHomeDirectory.path
        let containerHome = ToolboxPaths.containerHomeDirectory(userName: userName)

        // Build environment for the init script. Shell resolution is handled
        // inside the container by the init script reading /etc/os-release, so
        // we no longer inject the host SHELL.
        let imageConfig = try await image.config(for: platform).config
        var environment = imageConfig?.env ?? []
        let toolboxOverrides: [(String, String)] = [
            ("APPLEBOX_USER", userName),
            ("APPLEBOX_UID", "\(uid)"),
            ("APPLEBOX_GID", "\(gid)"),
            ("APPLEBOX_HOME", containerHome),
            ("APPLEBOX_CONTAINER_NAME", name),
            ("APPLEBOX_IMAGE", image.reference),
            ("LANG", ProcessInfo.processInfo.environment["LANG"] ?? "C.UTF-8"),
            ("TERM", ProcessInfo.processInfo.environment["TERM"] ?? "xterm-256color"),
        ]
        for (key, value) in toolboxOverrides {
            environment.removeAll { $0.hasPrefix("\(key)=") }
            environment.append("\(key)=\(value)")
        }

        // The init script at /sbin.applebox/init is PID 1. In boot mode (no
        // flags) it performs hostname setup, writes .containerenv, then execs
        // /sbin/init to hand off to the distro's real init system (systemd,
        // OpenRC, etc.), which keeps the container alive.
        let initProcess = ProcessConfiguration(
            executable: ToolboxPaths.containerInitPath,
            arguments: [],
            environment: environment,
            workingDirectory: "/",
            terminal: true,
            user: .id(uid: 0, gid: 0),
        )

        // Get or create the container home volume
        let containerHomeVolume: VolumeConfiguration
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
        let sbinDir = try ToolboxPaths.ensureHostSbinDirectory()

        Applebox.logger.debug(
            "configuring container",
            metadata: ["name": "\(name)", "runDir": "\(runDir.path)", "sbinDir": "\(sbinDir.path)"])

        var config = ContainerConfiguration(
            id: name, image: image.description, process: initProcess)
        config.platform = platform
        config.ssh = true
        config.resources = try Parser.resources(
            cpus: nil, memory: nil,
            defaultCPUs: ContainerConfig.defaultCPUs,
            defaultMemory: ContainerConfig.defaultMemory)

        config.labels = [
            ToolboxLabel.managed: "true"
        ]
        // Toolbox containers run a full init system (systemd, OpenRC) and act as
        // persistent development environments, so they need all capabilities.
        config.capAdd = ["ALL"]

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
            .virtiofs(
                source: sbinDir.path, destination: ToolboxPaths.containerSbinMountPoint,
                options: ["ro"]),
        ]

        // Set up networking
        let networkClient = NetworkClient()
        guard let builtin = try await networkClient.builtin else {
            throw AppleboxError.builtinNetworkNotPresent
        }
        Applebox.logger.debug("network state", metadata: ["network": "\(builtin.id)"])
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

    /// Ensures the container is running, starting it if stopped. The container's
    /// PID 1 is the distro's real init system (`/sbin/init`), so we just need to
    /// confirm the container reaches the running state.
    func ensureRunning(id: String) async throws -> ContainerSnapshot {
        var container = try await get(id: id)
        Applebox.logger.debug(
            "container status", metadata: ["id": "\(id)", "status": "\(container.status.rawValue)"])
        if container.status == .running {
            return container
        }
        if container.status == .stopped || container.status == .unknown {
            Applebox.logger.debug("starting stopped container", metadata: ["id": "\(id)"])

            let stdio: [FileHandle?] = [nil, nil, nil]
            var dynamicEnv: [String: String] = [:]
            if let sshAuthSock = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] {
                dynamicEnv["SSH_AUTH_SOCK"] = sshAuthSock
            }
            let process = try await bootstrap(id: id, stdio: stdio, dynamicEnv: dynamicEnv)
            try await process.start()

            // Wait for the container to confirm it's running. The distro's init
            // system (systemd/OpenRC) needs a moment to start.
            let deadline = ContinuousClock.now + .seconds(10)
            while ContinuousClock.now < deadline {
                container = try await get(id: id)
                if container.status == .running {
                    Applebox.logger.debug("container running", metadata: ["id": "\(id)"])
                    return container
                }
                try await Task.sleep(for: .milliseconds(200))
            }
            throw AppleboxError.containerInvalidState(
                "Container did not stay running after start. "
                    + "The image may not have /sbin/init.",
            )
        }
        throw AppleboxError.containerInvalidState(
            "container \(id) in unexpected state: \(container.status)",
        )
    }

    /// Ensures the container user has been created. On first entry after creation,
    /// runs the init script in user-setup mode (`-u`) which creates the user
    /// matching the host UID/GID with passwordless sudo.
    func ensureUserSetup(id: String, snapshot: ContainerSnapshot) async throws {
        let stampURL = ToolboxPaths.hostInitializedStampURL(for: id)
        if FileManager.default.fileExists(atPath: stampURL.path) {
            Applebox.logger.debug("user already initialized", metadata: ["id": "\(id)"])
            return
        }

        Applebox.logger.debug("running first-time user setup", metadata: ["id": "\(id)"])

        var setupConfig = snapshot.configuration.initProcess
        setupConfig.executable = ToolboxPaths.containerInitPath
        setupConfig.arguments = ["-u"]
        setupConfig.terminal = false
        setupConfig.user = .id(uid: 0, gid: 0)

        let io = try ProcessIO.create(tty: false, interactive: false, detach: false)
        defer { try? io.close() }

        let process = try await createProcess(
            containerId: id,
            processId: UUID().uuidString.lowercased(),
            configuration: setupConfig,
            stdio: io.stdio,
        )

        let exitCode = try await io.handleProcess(process: process, log: Applebox.logger)
        guard exitCode == 0 else {
            throw AppleboxError.userSetupFailed(id, exitCode: exitCode)
        }
        Applebox.logger.debug("user setup complete", metadata: ["id": "\(id)"])
    }
}
