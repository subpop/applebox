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
import Foundation

/// Supported Linux distributions using toolbox container images.
public enum SupportedDistro: String, CaseIterable, ExpressibleByArgument, Sendable {
    static let `default` = Self.alpine

    case fedora
    case ubuntu
    case arch
    case rhel
    case alpine
    case almalinux
    case amazonlinux
    case centos
    case debian
    case opensuse
    case rockylinux
    case wolfi

    public var containerNamePrefix: String {
        rawValue + "-toolbox"
    }

    public var defaultRelease: String {
        switch self {
        case .fedora: "43"
        case .ubuntu: "24.04"
        case .arch: "latest"
        case .rhel: "10.0"
        case .alpine: "3.22"
        case .almalinux: "9"
        case .amazonlinux: "2023"
        case .centos: "stream10"
        case .debian: "13"
        case .opensuse: "tumbleweed"
        case .rockylinux: "9"
        case .wolfi: "latest"
        }
    }

    private var registry: String {
        switch self {
        case .fedora: return "registry.fedoraproject.org"
        case .ubuntu, .arch: return "quay.io/toolbx"
        case .rhel: return "registry.access.redhat.com"
        case .alpine, .almalinux, .amazonlinux, .centos, .debian, .opensuse, .rockylinux, .wolfi:
            return "quay.io/toolbx-images"
        }
    }

    private func repository(release: String) -> String {
        switch self {
        case .rhel:
            let major = release.prefix(while: { $0 != "." })
            return "ubi\(major)/toolbox"
        default: return "\(rawValue)-toolbox"
        }
    }

    public func imageReference(release: String) -> String {
        "\(registry)/\(repository(release: release)):\(release)"
    }

    /// Validate and normalize a user-supplied release string.
    public func validateRelease(_ release: String) throws -> String {
        switch self {
        case .fedora:
            var r = release
            if r.hasPrefix("F") || r.hasPrefix("f") { r = String(r.dropFirst()) }
            guard let n = Int(r), n > 0 else {
                throw AppleboxError.invalidRelease("Fedora release must be a positive integer.")
            }
            return r

        case .ubuntu:
            let parts = release.split(separator: ".")
            guard parts.count == 2 else {
                throw AppleboxError.invalidRelease("Ubuntu release must be in 'YY.MM' format.")
            }
            let yearStr = String(parts[0])
            let monthStr = String(parts[1])
            guard let year = Int(yearStr), year >= 4, yearStr.count <= 2 else {
                throw AppleboxError.invalidRelease("Ubuntu release year must be 4–99.")
            }
            if year < 10, yearStr.count == 2 {
                throw AppleboxError.invalidRelease(
                    "Ubuntu release year cannot have a leading zero.")
            }
            guard let month = Int(monthStr), (1...12).contains(month), monthStr.count == 2 else {
                throw AppleboxError.invalidRelease("Ubuntu release month must be 01–12.")
            }
            return release

        case .arch:
            let r = release.lowercased()
            if r.isEmpty || r == "latest" || r == "rolling" { return "latest" }
            throw AppleboxError.invalidRelease("Arch release must be 'latest'.")

        case .rhel:
            let parts = release.split(separator: ".")
            guard parts.count == 2,
                let major = Int(parts[0]), major > 0,
                Int(parts[1]) != nil
            else {
                throw AppleboxError.invalidRelease("RHEL release must be in 'N.M' format.")
            }
            return release

        case .alpine:
            let r = release.lowercased()
            if r == "edge" {
                return "edge"
            }
            let parts = r.split(separator: ".")
            guard parts.count == 2,
                let major = Int(parts[0]), major >= 0,
                let minor = Int(parts[1]), minor >= 0
            else {
                throw AppleboxError.invalidRelease(
                    "Alpine release must be in 'N.M' format or 'edge'.")
            }
            return r

        case .almalinux:
            guard let n = Int(release), n > 0 else {
                throw AppleboxError.invalidRelease("Almalinux release must be a positive integer.")
            }
            return release

        case .amazonlinux:
            guard release == "2" || release == "2023" else {
                throw AppleboxError.invalidRelease("Amazonlinux release must be '2' or '2023'.")
            }
            return release

        case .centos:
            guard release == "stream10" || release == "stream9" else {
                throw AppleboxError.invalidRelease(
                    "Centos release must be 'stream10' or 'stream9'.")
            }
            return release

        case .debian:
            let r = release.lowercased()
            let validReleases = ["unstable", "testing", "13", "12", "11"]
            if validReleases.contains(r) {
                return r
            } else {
                throw AppleboxError.invalidRelease(
                    "Debian release must be one of: \(validReleases.joined(separator: ", ")).")
            }

        case .opensuse:
            let r = release.lowercased()
            if r == "tumbleweed" {
                return "tumbleweed"
            }
            throw AppleboxError.invalidRelease("OpenSUSE release must be 'tumbleweed'.")

        case .rockylinux:
            let r = release.lowercased()

            let validReleases = ["8", "9"]
            if validReleases.contains(r) {
                return r
            }
            throw AppleboxError.invalidRelease(
                "RockyLinux release must be one of: \(validReleases.joined(separator: ", ")).")

        case .wolfi:
            let r = release.lowercased()
            if r.isEmpty || r == "latest" || r == "rolling" { return "latest" }
            throw AppleboxError.invalidRelease("Wolfi release must be 'latest'.")
        }
    }
}
