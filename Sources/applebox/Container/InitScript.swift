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

enum InitScript {
    /// Shell script that serves as the container's main process, modeled after
    /// toolbox's ``init-container`` subcommand lifecycle:
    ///
    /// 1. User & environment setup
    /// 2. Marker file creation
    /// 3. Initialization stamp (written to the shared ``/run/applebox`` mount
    ///    so the host can detect completion)
    /// 4. Signal-aware event loop
    static let source = """
        set -e

        uid="$APPLEBOX_UID"
        guest_gid="${APPLEBOX_GUEST_GID:-1000}"
        user="$USER"
        home="$HOME"
        shell="$SHELL"

        if ! [ -x "$shell" ]; then
            shell=/bin/sh
        fi

        # Primary group: name matches user (Linux convention), guest GID
        getent group "$guest_gid" >/dev/null 2>&1 \
            || groupadd -g "$guest_gid" "$user" 2>/dev/null || true

        if id "$user" >/dev/null 2>&1; then
            usermod -u "$uid" -g "$guest_gid" -d "$home" -s "$shell" "$user" \
                2>/dev/null || true
        else
            useradd -u "$uid" -g "$guest_gid" -d "$home" -s "$shell" "$user" \
                2>/dev/null || true
        fi

        mkdir -p "$home" && chown "$uid":"$guest_gid" "$home"

        xdg_runtime_dir="/run/user/$uid"
        mkdir -p "$xdg_runtime_dir" && chown "$uid":"$guest_gid" "$xdg_runtime_dir"
        printf '%s' "$guest_gid" > /run/applebox/guest_gid
        printf '%s' "$xdg_runtime_dir" > /run/applebox/xdg_runtime_dir

        usermod -aG wheel "$user" 2>/dev/null \
            || usermod -aG sudo "$user" 2>/dev/null || true

        if [ -d /etc/sudoers.d ]; then
            echo "$user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/applebox
            chmod 440 /etc/sudoers.d/applebox
        fi

        passwd -d root 2>/dev/null || true

        # Write toolbox-compatible .containerenv (key=value format) for tools that parse it
        {
            echo "engine=container"
            echo "name=${APPLEBOX_CONTAINER_NAME:-}"
            echo "image=${APPLEBOX_IMAGE:-}"
            echo "rootless=1"
        } > /run/.containerenv

        printf '%s' "$shell" > /run/applebox/shell
        touch /run/applebox/initialized

        trap 'exit 0' TERM INT

        while true; do
            sleep 86400 &
            wait $!
        done
        """
}
