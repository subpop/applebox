# Applebox

**box** — persistent Linux development containers for macOS. Create toolbox-style containers, share your home directory, and get an interactive shell with your host user and environment.

![apple box](./applebox.png)

## Features

- **Create** persistent containers from Fedora, Ubuntu, Arch, or RHEL toolbox images, or any OCI image
- **Enter** an interactive shell with your host UID/GID, `$HOME` bind-mounted, and `$SHELL` preserved
- **Run** a single command in a container
- **List** containers with name, start time, status, and image
- **Remove** containers (with optional force) and clean up runtime data
- Configurable **log level** (`--log-level`) for debugging

## Prerequisites

- **macOS 26** or later
- **Swift 6.2** (Xcode or Swift toolchain)
- **[Apple Container runtime](https://github.com/apple/container) 0.10.0 or later**

## Installation

### [Mint](https://github.com/yonaskolb/mint)

```
mint install subpop/applebox
```

### From source (Swift Package Manager)

```bash
git clone https://github.com/subpop/applebox.git
cd applebox
swift build -c release
```

Install the `box` binary into your PATH (optional):

```bash
install .build/release/box /usr/local/bin/box
# or
cp .build/release/box ~/bin/box
```

### Shell completions (optional)

`box` can generate completion scripts for **Bash**, **Zsh**, and **Fish**. Completions include subcommands and options; the `enter` and `rm` commands also complete container names from your toolbox list.

Generate a script for your shell:

```bash
box --generate-completion-script bash   # Bash
box --generate-completion-script zsh    # Zsh
box --generate-completion-script fish   # Fish
```

**Bash:** With [bash-completion](https://github.com/scop/bash-completion) installed, save the script to a directory that bash-completion uses (e.g. `/usr/local/etc/bash_completion.d/box`). Otherwise, save it (e.g. to `~/.bash_completions/box.bash`) and add to `~/.bashrc` or `~/.bash_profile`:

```bash
source ~/.bash_completions/box.bash
```

**Zsh:** With [oh-my-zsh](https://ohmyz.sh), save as `_box` in the completions directory:

```bash
box --generate-completion-script zsh > ~/.oh-my-zsh/completions/_box
```

Without oh-my-zsh, add a completion path to `~/.zshrc` (e.g. `fpath=(~/.zsh/completion $fpath)`, run `autoload -U compinit && compinit`), then put the generated script in that directory as `_box`.

**Fish:** Save the script to a path in `$fish_completion_path`, for example:

```bash
box --generate-completion-script fish > ~/.config/fish/completions/box.fish
```

## Example usage

Create a Fedora 42 toolbox (default distro and release):

```bash
box create
# prints default name, e.g. fedora-toolbox-42
```

Create a named Ubuntu 24.04 container:

```bash
box create --distro ubuntu --release 24.04 my-ubuntu
```

Create from a custom OCI image:

```bash
box create --image docker.io/library/debian:bookworm my-debian
```

Enter the default container (Fedora 42) or a named one:

```bash
box enter
box enter my-ubuntu
```

Run a single command in a container (default or named):

```bash
box run my-ubuntu cat /etc/os-release
echo "hello" | box run my-ubuntu cat
```

List containers:

```bash
box list
```

Remove one or more containers:

```bash
box rm my-ubuntu
box rm -f container1 container2
```

Use a higher log level for troubleshooting:

```bash
box --log-level debug create --distro arch
```

## License

Apache 2.0. See the LICENSE file for details.
