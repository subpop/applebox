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

import ArgumentParser
import ContainerAPIClient
import Foundation
import Logging

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a single command in a container",
    )

    @OptionGroup var options: GlobalOptions

    @Argument(
        help: "Container name",
        completion: .custom(ContainerCompletions.containerNames)
    )
    var container: String?

    @Argument(
        parsing: .captureForPassthrough,
        help: "Command and arguments to run inside the container"
    )
    var command: [String] = []

    func run() async throws {
        Applebox.applyLogging(options)

        guard !command.isEmpty else {
            throw ValidationError("At least one command argument is required.")
        }

        let name =
            container
            ?? "\(SupportedDistro.default.containerNamePrefix)-\(SupportedDistro.default.defaultRelease)"

        Applebox.logger.debug(
            "run command started",
            metadata: ["container": "\(name)", "command": "\(command.joined(separator: " "))"])

        let client = ContainerClient()
        Applebox.logger.debug("ensuring container is running", metadata: ["container": "\(name)"])
        let snapshot = try await client.ensureRunning(id: name)

        // Ensure first-time user setup has been performed
        try await client.ensureUserSetup(id: name, snapshot: snapshot)

        // Use the init script in shell mode (-s command args...) to resolve the
        // distro-appropriate shell and run the command through it.
        var config = snapshot.configuration.initProcess
        config.executable = ToolboxPaths.containerInitPath
        config.arguments = ["-s"] + command
        config.terminal = false
        config.user = .id(uid: getuid(), gid: getgid())
        config.workingDirectory = ToolboxPaths.resolvedWorkingDirectory()

        let io = try ProcessIO.create(tty: false, interactive: true, detach: false)
        defer { try? io.close() }

        let process = try await client.createProcess(
            containerId: name,
            processId: UUID().uuidString.lowercased(),
            configuration: config,
            stdio: io.stdio,
        )

        let exitCode = try await io.handleProcess(process: process, log: Applebox.logger)
        throw ExitCode(exitCode)
    }
}
