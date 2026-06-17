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

struct Enter: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enter",
        abstract: "Enter a container for interactive use",
    )

    @OptionGroup var options: GlobalOptions

    @Argument(
        help: "Container name",
        completion: .custom(ContainerCompletions.containerNames)
    )
    var container: String?

    func run() async throws {
        Applebox.applyLogging(options)

        let name =
            container
            ?? "\(SupportedDistro.default.containerNamePrefix)-\(SupportedDistro.default.defaultRelease)"

        Applebox.logger.debug("enter command started", metadata: ["container": "\(name)"])

        let client = ContainerClient()
        Applebox.logger.debug("ensuring container is running", metadata: ["container": "\(name)"])
        let snapshot = try await client.ensureRunning(id: name)

        // Ensure first-time user setup has been performed
        try await client.ensureUserSetup(id: name, snapshot: snapshot)

        Applebox.logger.debug(
            "starting shell in container",
            metadata: [
                "container": "\(name)",
                "workingDirectory": "\(FileManager.default.currentDirectoryPath)",
            ])

        // Use the init script in shell mode (-s) to resolve the distro-appropriate
        // shell and exec into a login shell.
        var config = snapshot.configuration.initProcess
        config.executable = ToolboxPaths.containerInitPath
        config.arguments = ["-s"]
        config.terminal = true
        config.user = .id(uid: getuid(), gid: getgid())
        config.workingDirectory = ToolboxPaths.resolvedWorkingDirectory()

        let io = try ProcessIO.create(tty: true, interactive: true, detach: false)
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
