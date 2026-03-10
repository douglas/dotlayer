# dotlayer

A convention-driven CLI wrapper around [GNU Stow](https://www.gnu.org/software/stow/) for managing dotfiles across multiple machines with layered overrides.

## Why

Managing dotfiles across machines with different OSes, hardware profiles, and Linux distros means lots of conditional logic in install scripts. Dotlayer replaces that with a naming convention: directory names declare when they should be stowed.

```
config/                     → always stowed
config-linux/               → stowed on Linux
config-macos/               → stowed on macOS
config-omarchy/             → stowed when Omarchy is detected
config-omarchy-desktop/     → stowed on Omarchy + desktop profile
config-omarchy-laptop/      → stowed on Omarchy + laptop profile
```

No config file needed — just name your directories and dotlayer figures out the rest.

## Install

```sh
gem install dotlayer
```

Or clone and run directly:

```sh
git clone https://github.com/douglas/dotlayer.git
export PATH="$HOME/src/dotlayer/exe:$PATH"
```

**Requirements:** Ruby >= 3.2, GNU Stow

## Quick start

```sh
# See what dotlayer detects on your system
dotlayer status

# Stow all matching packages
dotlayer install

# Pull latest changes and re-stow
dotlayer update

# Check for broken symlinks and missing deps
dotlayer doctor
```

## How it works

Dotlayer auto-detects three things about your system:

| Detection | Method | Example |
|-----------|--------|---------|
| **OS** | `RbConfig::CONFIG["host_os"]` | `linux`, `macos` |
| **Profile** | `hostnamectl chassis` or `$DOTLAYER_PROFILE` | `desktop`, `laptop` |
| **Distro** | Shell commands from config | `omarchy`, `fedora` |

It then scans your dotfiles repo for directories matching these tags and stows them in layer order:

1. **Base packages** — `stow`, `bin`, `git`, `zsh`, `config`
2. **OS layer** — `config-linux` or `config-macos`
3. **Distro layer** — `config-omarchy`
4. **Distro + profile** — `config-omarchy-desktop`

Each layer can add files but never conflict with earlier layers (Stow constraint).

## Configuration

Dotlayer works with zero configuration using sensible defaults. For customization, create a `dotlayer.yml`:

```yaml
target: ~

repos:
  - path: ~/.public_dotfiles
  - path: ~/.private_dotfiles
    private: true

packages:
  - stow
  - bin
  - git
  - zsh
  - config

profiles:
  detect: hostnamectl chassis
  env: DOTLAYER_PROFILE

distros:
  omarchy:
    detect: test -d ~/.local/share/omarchy
  fedora:
    detect: . /etc/os-release && test "$ID" = "fedora"

system_files:
  - source: config-linux/etc/systemd/system-sleep/xremap-restart.sh
    dest: /etc/systemd/system-sleep/xremap-restart.sh
    mode: "0755"

hooks:
  after_system_files:
    - sudo udevadm control --reload-rules
```

## CLI reference

```
dotlayer [options] <command>

Commands:
  install     Detect system, stow all layers, install system files
  update      Pull repos, re-stow all layers
  status      Show detected OS, profile, distros, and packages
  doctor      Check for broken symlinks, conflicts, missing deps
  version     Print version

Options:
  -c, --config PATH   Config file path
  -n, --dry-run       Show what would be done without making changes
  -v, --verbose       Verbose output
```

## Documentation

- [Architecture](docs/architecture.md) — system design, data flow, and class responsibilities
- [Contributing](CONTRIBUTING.md) — setup, testing, and contribution guidelines

## License

[O-SaaSy](https://osaasy.dev)
