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

@testable import Applebox
import Foundation
import Testing

enum SupportedDistroTests {
    struct ReleaseValidation {
        @Test func fedora() throws {
            #expect(try SupportedDistro.fedora.validateRelease("42") == "42")
            #expect(try SupportedDistro.fedora.validateRelease("F42") == "42")
            #expect(try SupportedDistro.fedora.validateRelease("f41") == "41")
            #expect(throws: AppleboxError.self) {
                try SupportedDistro.fedora.validateRelease("0")
            }
            #expect(throws: AppleboxError.self) {
                try SupportedDistro.fedora.validateRelease("x")
            }
        }

        @Test func ubuntu() throws {
            #expect(try SupportedDistro.ubuntu.validateRelease("24.04") == "24.04")
            #expect(try SupportedDistro.ubuntu.validateRelease("22.04") == "22.04")
            #expect(throws: AppleboxError.self) {
                try SupportedDistro.ubuntu.validateRelease("24")
            }
            #expect(throws: AppleboxError.self) {
                try SupportedDistro.ubuntu.validateRelease("3.04")
            }
        }

        @Test func arch() throws {
            #expect(try SupportedDistro.arch.validateRelease("latest") == "latest")
            #expect(try SupportedDistro.arch.validateRelease("rolling") == "latest")
            #expect(try SupportedDistro.arch.validateRelease("") == "latest")
            #expect(throws: AppleboxError.self) {
                try SupportedDistro.arch.validateRelease("42")
            }
        }

        @Test func rhel() throws {
            #expect(try SupportedDistro.rhel.validateRelease("9.4") == "9.4")
            #expect(try SupportedDistro.rhel.validateRelease("8.10") == "8.10")
            #expect(throws: AppleboxError.self) {
                try SupportedDistro.rhel.validateRelease("9")
            }
        }
    }

    struct ImageReference {
        @Test func fedora() {
            #expect(
                SupportedDistro.fedora.imageReference(release: "42")
                    == "registry.fedoraproject.org/fedora-toolbox:42",
            )
        }

        @Test func ubuntu() {
            #expect(
                SupportedDistro.ubuntu.imageReference(release: "24.04")
                    == "quay.io/toolbx/ubuntu-toolbox:24.04",
            )
        }

        @Test func arch() {
            #expect(
                SupportedDistro.arch.imageReference(release: "latest")
                    == "quay.io/toolbx/arch-toolbox:latest",
            )
        }

        @Test func rhel() {
            #expect(
                SupportedDistro.rhel.imageReference(release: "9.4")
                    == "registry.access.redhat.com/ubi9/toolbox:9.4",
            )
        }
    }

    struct ContainerNaming {
        @Test func `default names`() {
            #expect(SupportedDistro.fedora.containerNamePrefix == "fedora-toolbox")
            #expect(SupportedDistro.ubuntu.containerNamePrefix == "ubuntu-toolbox")
            #expect(SupportedDistro.arch.containerNamePrefix == "arch-toolbox")
            #expect(SupportedDistro.rhel.containerNamePrefix == "rhel-toolbox")
        }
    }
}
