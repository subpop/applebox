## 0.2.0 (2026-06-17)

- 🚀 Update apple/container dependency to 1.0.0 and apple/containerization to 0.33.3
- 🔧 Exec into distro init system (systemd, OpenRC) instead of custom sleep loop
- 🏗️ Multi-mode init script: boot, shell resolution, and user setup as separate concerns
- 🔑 Grant all Linux capabilities to toolbox containers for proper init system boot
- 🐛 Fix container enter failures caused by reduced default capability set in container 1.0.0
- 🐛 Fix virtiofs mount hidden by systemd tmpfs remount (move runtime mount to `/var/lib/applebox`)
- 🧹 Remove entitlements
- 📝 Add AGENTS.md guidelines

## 0.1.5 (2026-05-26)

- 🔧 Dynamic `SSH_AUTH_SOCK` environment variable at bootstrap to handle ssh socket path change in container 0.12.x

## 0.1.4 (2026-04-29)

- ⬆️ Update minimum version of apple/container to 0.12
- 🔧 Use `NetworkClient()` instead of `ClientNetwork.builtin` singleton for network access
- 🔧 Add `ContainerCommands` dependency for `TableOutput` import

## 0.1.3 (2026-04-21)

- 🐛 Filter `list` output to only show toolbox containers

## 0.1.2 (2026-04-02)

- ✨ Add `run` command for executing commands in containers
- ⬆️ Update to apple/container 0.11.0
- 🐛 Use empty nameservers to force containers to discover DNS from the attached network device at every start

## 0.1.1 (2026-03-11)

- 💾 Create persistent volume for container `/home`
- 🔧 Use `ssh` option in `ContainerConfiguration` to mount ssh agent instead of mounting the directory directly
- 🔧 Move image fetch and progress UI into `Create` command
- 🔧 Refactor `Enter` command to use current working directory instead of container home
- 🧹 Clean up init script and remove unused `/run/.appleboxenv` file

## 0.1.0 (2026-03-10)

- 🎁 Initial project release
