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

    /// Root cache directory for applebox state.
    private static var hostCacheRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(
                path: "Library/Caches/dev.applebox",
                directoryHint: .isDirectory
            )
    }

    /// Per-container directory on the host, shared into the container at
    /// ``containerRuntimeMountPoint`` via virtiofs. The user setup script writes an
    /// initialization stamp here so the host can detect first-run completion.
    static func hostRuntimeDirectory(for name: String) -> URL {
        hostCacheRoot.appending(path: name, directoryHint: .isDirectory)
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

    /// URL of the "initialized" stamp file in the host runtime dir (created on first user setup).
    static func hostInitializedStampURL(for name: String) -> URL {
        hostRuntimeDirectory(for: name)
            .appending(path: "initialized", directoryHint: .notDirectory)
    }

    // MARK: - Host sbin directory

    /// Shared directory on the host containing the init and create-user scripts, mounted
    /// read-only into every container at ``containerSbinMountPoint``.
    static var hostSbinDirectory: URL {
        hostCacheRoot
            .appending(path: "sbin.applebox", directoryHint: .isDirectory)
    }

    /// Materializes the init and create-user scripts into ``hostSbinDirectory`` if they
    /// are missing or out of date, so they can be bind-mounted into the container.
    static func ensureHostSbinDirectory() throws -> URL {
        let dir = hostSbinDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let initDest = dir.appending(path: "init", directoryHint: .notDirectory)
        let setupDest = dir.appending(
            path: "create-user.sh",
            directoryHint: .notDirectory
        )

        // Always overwrite so running containers pick up script changes after
        // an applebox upgrade.
        try initScriptSource.write(to: initDest, atomically: true, encoding: .utf8)
        try createUserScriptSource.write(to: setupDest, atomically: true, encoding: .utf8)

        // Ensure executable
        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: initDest.path)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: setupDest.path)

        return dir
    }

    // MARK: - Container paths

    /// Mount point inside the container where the host runtime directory is visible.
    /// Uses /var/lib/applebox rather than /run/applebox because systemd remounts
    /// /run as tmpfs during early boot, hiding any virtiofs mounts underneath it.
    static let containerRuntimeMountPoint = "/var/lib/applebox"

    /// Mount point inside the container for the applebox sbin scripts (init, create-user).
    static let containerSbinMountPoint = "/sbin.applebox"

    /// Path to the init script inside the container.
    static let containerInitPath = "\(containerSbinMountPoint)/init"

    /// Home directory used inside the container. Distinct from the host home so that Linux
    /// executables and config work correctly; the host home is still mounted separately
    /// for direct file access.
    static func containerHomeDirectory(userName: String) -> String {
        "/home/\(userName)"
    }

    // MARK: - Resolution

    /// Returns the working directory to use inside the container. If the host CWD
    /// is under the user's home directory (which is mounted into the container),
    /// mirrors it inside the container. Otherwise falls back to the user's container
    /// home directory.
    static func resolvedWorkingDirectory() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cwd = FileManager.default.currentDirectoryPath
        if cwd.hasPrefix(home) {
            return cwd
        }
        let userName = ProcessInfo.processInfo.userName
        return containerHomeDirectory(userName: userName)
    }

    // MARK: - Script sources

    /// The init script source, embedded as a string constant so it can be written to disk
    /// at runtime without requiring SPM resource bundling.
    static let initScriptSource = """
        #!/bin/sh
        #
        # Applebox init script — the first process (PID 1) executed when a container
        # boots. Performs container-specific setup before handing off to the real
        # system init.
        #
        #   Boot mode (no flags):
        #     Sets the hostname, writes .containerenv, fixes SSH socket ownership,
        #     and execs /sbin/init to hand off to the real system init.
        #
        #   Shell mode (-s [command...]):
        #     Resolves the user's shell from /etc/passwd with distro-aware fallbacks,
        #     then execs into it.
        #
        #   User setup mode (-u):
        #     Creates the container user on first run via create-user.sh.
        #

        set -e

        INITIALIZED=/var/lib/applebox/initialized
        CUSTOM_SETUP=/etc/applebox/create-user.sh
        DEFAULT_SETUP=/sbin.applebox/create-user.sh

        # Resolve distro-appropriate default shell
        . /etc/os-release 2>/dev/null || true
        case "${ID:-}" in
            ubuntu|debian)
                SHELL=$(unset DSHELL; . /etc/adduser.conf 2>/dev/null \\
                    && [ -n "${DSHELL:-}" ] \\
                    && echo "${DSHELL}") || SHELL=/bin/bash ;;
            *)
                SHELL=$(unset SHELL; . /etc/default/useradd 2>/dev/null \\
                    && [ -n "${SHELL:-}" ] \\
                    && echo "${SHELL}") || SHELL=/bin/sh ;;
        esac
        export CONTAINER_SHELL=${SHELL}

        if [ "$1" = "-s" ]; then
            # Shell mode: resolve user's shell, exec into it
            shift
            USER_SHELL=$(grep "^$(id -un):" /etc/passwd 2>/dev/null | cut -d: -f7)
            if [ $# -gt 0 ]; then
                exec "${USER_SHELL:-${SHELL}}" -c "$*"
            else
                exec "${USER_SHELL:-${SHELL}}" -l
            fi
        elif [ "$1" = "-u" ]; then
            # User setup mode: create user if not exists
            if ! id "${APPLEBOX_USER}" >/dev/null 2>&1; then
                if [ -f "${CUSTOM_SETUP}" ]; then
                    ${CUSTOM_SETUP}
                else
                    ${DEFAULT_SETUP}
                fi
            fi
            echo 1 > ${INITIALIZED}
        else
            # Boot mode: set hostname, write containerenv, exec real init
            echo "${APPLEBOX_CONTAINER_NAME}" > /etc/hostname

            if [ -S "${SSH_AUTH_SOCK:-}" ]; then
                chown "${APPLEBOX_UID}:${APPLEBOX_GID}" "${SSH_AUTH_SOCK}"
            fi

            {
                echo "engine=container"
                echo "name=${APPLEBOX_CONTAINER_NAME:-}"
                echo "image=${APPLEBOX_IMAGE:-}"
                echo "rootless=1"
            } > /run/.containerenv

            if [ -x /sbin/init ]; then
                exec /sbin/init
            else
                exec sleep infinity
            fi
        fi
        """

    /// The create-user script source, embedded as a string constant.
    static let createUserScriptSource = """
        #!/bin/sh
        #
        # First-time container user setup. Distro-agnostic by directly manipulating
        # /etc/group, /etc/passwd, and /etc/shadow rather than relying on
        # image-specific tools (useradd, adduser, etc.).
        #

        set -e

        if ! getent group "${APPLEBOX_GID}" >/dev/null 2>&1; then
            echo "${APPLEBOX_USER}:x:${APPLEBOX_GID}:" >> /etc/group
        fi

        if ! getent passwd "${APPLEBOX_UID}" >/dev/null 2>&1; then
            echo "${APPLEBOX_USER}:x:${APPLEBOX_UID}:${APPLEBOX_GID}::${APPLEBOX_HOME}:${CONTAINER_SHELL}" >> /etc/passwd
            echo "${APPLEBOX_USER}:!:19000:0:99999:7:::" >> /etc/shadow
        fi

        mkdir -p "${APPLEBOX_HOME}"
        if [ -d /etc/skel ]; then
            cp -a /etc/skel/. "${APPLEBOX_HOME}"
        fi
        chown -R "${APPLEBOX_UID}:${APPLEBOX_GID}" "${APPLEBOX_HOME}"

        mkdir -p /etc/sudoers.d
        echo "${APPLEBOX_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/applebox
        chmod 440 /etc/sudoers.d/applebox
        """
}
