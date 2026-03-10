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

struct Rm: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Remove one or more containers",
    )

    @OptionGroup var options: GlobalOptions

    @Flag(name: [.long, .short], help: "Force removal")
    var force = false

    @Argument(
        help: "Container name(s) to remove",
        completion: .custom(ContainerCompletions.containerNames)
    )
    var containers: [String] = []

    func run() async throws {
        Applebox.applyLogging(options)
        guard !containers.isEmpty else {
            throw ValidationError("At least one container name is required.")
        }
        Applebox.logger.debug(
            "rm command started",
            metadata: [
                "containers": "\(containers.joined(separator: ", "))",
                "force": "\(force)",
            ])
        let client = ContainerClient()
        for name in containers {
            Applebox.logger.debug("stopping container", metadata: ["container": "\(name)"])
            try await client.stop(id: name)
            Applebox.logger.debug(
                "deleting container", metadata: ["container": "\(name)", "force": "\(force)"])
            try await client.delete(id: name, force: force)
            let runDir = ToolboxPaths.hostRuntimeDirectory(for: name)
            try? FileManager.default.removeItem(at: runDir)
            Applebox.logger.debug(
                "removed container and runtime dir", metadata: ["container": "\(name)"])
            print("\(name)")
        }
    }
}
