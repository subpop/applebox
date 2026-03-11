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

import Foundation

/// Centralized host and container path naming, creation, and resolution for toolbox containers.
/// Host paths are on the macOS filesystem; container paths are as seen inside the Linux container.
enum ToolboxPaths {
    // MARK: - Host paths

    /// Per-container directory on the host, shared into the container at
    /// ``containerRuntimeMountPoint`` via virtiofs. The init script writes its
    /// initialization stamp and shell path here so the host can detect completion.
    static func hostRuntimeDirectory(for name: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/dev.applebox/\(name)")
    }

    /// Creates the host runtime directory for the given container name if needed; returns its URL.
    static func ensureHostRuntimeDirectory(for name: String) throws -> URL {
        let dir = hostRuntimeDirectory(for: name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Path to the current user's home directory on the host (used as virtiofs source).
    static var hostHomeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    /// Path to the host user's `.ssh` directory. Mounted into the container at
    /// ``containerSSHDirectory(userName:)`` when present so `~/.ssh` works for ssh/git.
    static var hostSSHDirectory: URL {
        hostHomeDirectory.appendingPathComponent(".ssh", isDirectory: true)
    }

    /// Returns the host `.ssh` URL if it exists and is a directory; otherwise nil.
    static var hostSSHDirectoryIfPresent: URL? {
        let url = hostSSHDirectory
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
            isDir.boolValue
        else { return nil }
        return url
    }

    /// URL of the "shell" file in the host runtime dir (written by init; contains resolved shell path).
    static func hostRuntimeShellFile(for name: String) -> URL {
        hostRuntimeDirectory(for: name).appendingPathComponent("shell")
    }

    /// URL of the "initialized" stamp file in the host runtime dir (created when init completes).
    static func hostInitializedStampURL(for name: String) -> URL {
        hostRuntimeDirectory(for: name).appendingPathComponent("initialized")
    }

    /// URL of the "guest_gid" file in the host runtime dir (written by init; guest primary GID).
    static func hostRuntimeGuestGidFile(for name: String) -> URL {
        hostRuntimeDirectory(for: name).appendingPathComponent("guest_gid")
    }

    // MARK: - Container paths

    /// Mount point inside the container where the host runtime directory is visible.
    static let containerRuntimeMountPoint = "/run/applebox"

    /// Home directory used inside the container. Distinct from the host home so that Linux
    /// executables and config work correctly; the host home is still mounted at
    /// ``containerMountPointForHostHome(userName:)`` for access.
    static func containerHomeDirectory(userName: String) -> String {
        "/home/\(userName)"
    }

    /// Path inside the container for the user's `.ssh` directory (i.e. `$HOME/.ssh`).
    /// When host ``hostSSHDirectoryIfPresent`` is non-nil, it is mounted here so SSH keys are available.
    static func containerSSHDirectory(userName: String) -> String {
        "\(containerHomeDirectory(userName: userName))/.ssh"
    }

    // MARK: - Resolution

    /// Shell path to use when entering the container. Reads the path resolved by the init script
    /// from the host runtime dir; falls back to host `$SHELL` (then `/bin/sh`) when the file
    /// is missing, e.g. for containers created before this feature.
    static func resolvedShell(for name: String) -> String {
        let shellFile = hostRuntimeShellFile(for: name)
        if let contents = try? String(contentsOf: shellFile, encoding: .utf8),
            !contents.isEmpty
        {
            return contents
        }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/sh"
    }

    /// Guest primary GID to use when entering the container. Reads the value written by the init
    /// script so the process runs with the guest's user-named primary group; falls back to host
    /// `getgid()` for containers created before the guest primary group feature.
    static func resolvedGuestGid(for name: String) -> UInt32 {
        let file = hostRuntimeGuestGidFile(for: name)
        guard let contents = try? String(contentsOf: file, encoding: .utf8),
            let gid = UInt32(contents.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return getgid()
        }
        return gid
    }
}
