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
import ContainerizationOCI
import Foundation
import Logging

struct Create: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new persistent container",
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: [.long, .short], help: "Linux distribution")
    var distro: SupportedDistro?

    @Option(name: [.long, .short], help: "OCI image reference (cannot be used with --distro)")
    var image: String?

    @Option(name: [.long, .short], help: "Release (cannot be used with --image)")
    var release: String?

    @Argument(help: "Optional container name")
    var container: String?

    func run() async throws {
        Applebox.applyLogging(options)

        Applebox.logger.debug(
            "create command started",
            metadata: [
                "distro": "\(distro?.rawValue ?? "nil")",
                "image": "\(image ?? "nil")",
                "release": "\(release ?? "nil")",
                "container": "\(container ?? "nil")",
            ])

        if image != nil, distro != nil {
            throw AppleboxError.mutuallyExclusiveFlags("--image and --distro cannot be combined.")
        }
        if image != nil, release != nil {
            throw AppleboxError.mutuallyExclusiveFlags("--image and --release cannot be combined.")
        }

        let (imageRef, name) = try {
            guard let image else {
                let d = distro ?? .default
                let r = try d.validateRelease(release ?? d.defaultRelease)
                Applebox.logger.debug(
                    "resolved image from distro",
                    metadata: [
                        "distro": "\(d.rawValue)",
                        "release": "\(r)",
                        "imageRef": "\(d.imageReference(release: r))",
                    ])
                return (d.imageReference(release: r), container ?? "\(d.containerNamePrefix)-\(r)")
            }
            let ref = try Reference.parse(image)
            let lastPathComponent = ref.path.split(separator: "/").last.map(String.init) ?? ref.path

            return (
                image,
                container
                    ?? "\(lastPathComponent)-\(ref.tag ?? "latest")".replacingOccurrences(
                        of: "/", with: "-"),
            )
        }()

        Applebox.logger.debug(
            "creating toolbox",
            metadata: [
                "name": "\(name)",
                "imageReference": "\(imageRef)",
            ])

        let client = ContainerClient()
        try await client.createToolbox(name: name, imageReference: imageRef)
        Applebox.logger.debug("toolbox created successfully", metadata: ["name": "\(name)"])
        print(name)
    }
}
