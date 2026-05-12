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
config-omarchy-laptop-t14/  → stowed on Omarchy + laptop profile + t14 machine
config-mycompany/            → stowed when mycompany group is detected
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

# Move existing config into a stow package
dotlayer adopt ~/.config/lazygit config

# Move config into the private repo
dotlayer adopt --private ~/.config/lazysql config
```

## How it works

Dotlayer auto-detects five things about your system:

| Detection | Method | Example |
|-----------|--------|---------|
| **OS** | `RbConfig::CONFIG["host_os"]` | `linux`, `macos` |
| **Profile** | `hostnamectl chassis` or `$DOTLAYER_PROFILE` | `desktop`, `laptop` |
| **Machine** | `$DOTLAYER_MACHINE`, configured shell commands, then `hostname -s` fallback | `t14`, `framework-desktop` |
| **Distro** | Shell commands from config | `omarchy`, `fedora` |
| **Group** | Shell commands from config | `work`, `mycompany` |

It then scans your dotfiles repo for directories matching these tags and stows them in layer order:

1. **Base packages** — `stow`, `bin`, `git`, `zsh`, `config`
2. **OS layer** — `config-linux` or `config-macos`
3. **Distro layer** — `config-omarchy`
4. **Distro + profile** — `config-omarchy-desktop`
5. **Machine layer** — `config-t14`
6. **OS + machine** — `config-linux-t14`
7. **Distro + machine** — `config-omarchy-t14`
8. **Distro + profile + machine** — `config-omarchy-laptop-t14`
9. **Group layer** — `config-mycompany`

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

machines:
  env: DOTLAYER_MACHINE
  t14:
    detect: model="$(cat /sys/class/dmi/id/product_name /sys/class/dmi/id/product_version 2>/dev/null)"; case "$model" in *T14*) exit 0 ;; *) exit 1 ;; esac

distros:
  omarchy:
    detect: test -d ~/.local/share/omarchy
  fedora:
    detect: . /etc/os-release && test "$ID" = "fedora"

groups:
  mycompany:
    detect: test -d ~/src/mycompany

system_files:
  - source: config-linux/etc/systemd/system-sleep/xremap-restart.sh
    dest: /etc/systemd/system-sleep/xremap-restart.sh
    mode: "0755"

hooks:
  after_system_files:
    - sudo udevadm control --reload-rules
```

Config file is discovered automatically from:
- `~/.config/dotlayer/dotlayer.yml`
- `~/.public_dotfiles/dotlayer.yml`
- `~/.dotfiles/dotlayer.yml`

## Public and private dotfiles

Most people have two kinds of config: stuff you can share (shell aliases, editor themes, window manager rules) and stuff you can't (API keys, work credentials, employer-specific tooling). Dotlayer handles this with two repos:

```
~/.public_dotfiles/     ← shared on GitHub, safe for the world to see
~/.private_dotfiles/    ← private repo (or not pushed at all)
```

### Why two repos?

A single dotfiles repo forces a choice: keep it private (lose the benefit of sharing) or keep it public (risk leaking secrets). Two repos solves this cleanly:

- **Public repo** — your shell, editor, git, and desktop config. Push to GitHub, share with the community, clone on any new machine.
- **Private repo** — work-specific config, API tokens, SSH configs, fonts with restrictive licenses, employer tooling. Keep in a private repo or don't push at all.

Both repos stow into the same target (`~`), so your home directory looks the same regardless of which repo a file came from.

### Setting it up

Create both repos:

```sh
mkdir -p ~/.public_dotfiles ~/.private_dotfiles
cd ~/.public_dotfiles && git init
cd ~/.private_dotfiles && git init
```

Add the dotlayer config at `~/.config/dotlayer/dotlayer.yml`:

```yaml
repos:
  - path: ~/.public_dotfiles
  - path: ~/.private_dotfiles
    private: true
    packages:
      - config
      - fonts
    standalone_packages:
      - claude
      - shared
    group_packages:
      mycompany:
        - work
```

The `private: true` flag tells dotlayer which repo to use when you run `dotlayer adopt --private`.
`standalone_packages` is an allowlist for non-layered packages in that repo.
`group_packages` lets a group detection rule opt in exact package names like `work`
that do not follow the `config-mycompany` suffix convention.

### What goes where?

**Public repo** — uses the standard base packages (`stow`, `bin`, `git`, `zsh`, `config`) with full layering support:

```
~/.public_dotfiles/
  config/                       ← shared config (editor, terminal, etc.)
  config-linux/                 ← Linux-specific overrides
  config-omarchy/               ← Omarchy distro overrides
  config-omarchy-desktop/       ← Omarchy + desktop profile
  config-omarchy-laptop/        ← Omarchy + laptop profile
  config-omarchy-laptop-t14/    ← Omarchy + laptop profile + machine model
  git/                          ← git config
  zsh/                          ← shell config
  bin/                          ← personal scripts
  stow/                         ← stow's own config
```

**Private repo** — can use per-repo packages for layered resolution, plus standalone directories that are all stowed automatically:

```
~/.private_dotfiles/
  config/                       ← private config overlays (SSH, API keys)
  config-mycompany/              ← work-specific config (group layer)
  fonts/                        ← licensed fonts
  fonts-linux/                  ← Linux-specific font config
  claude/                       ← standalone: Claude AI config
  work/                         ← group package: work tooling
  scripts/                      ← standalone: work automation scripts
```

Directories that match the per-repo base packages (`config`, `fonts`) get full layer resolution. If `standalone_packages`
is omitted, every other top-level directory (`claude`, `scripts`) is stowed as-is in alphabetical order. If it is present,
only those allowlisted standalone packages are stowed. Exact work packages can be gated behind detected groups with
`group_packages`.

### Adopting files into the right repo

```sh
# Public config — goes to ~/.public_dotfiles
dotlayer adopt ~/.config/lazygit config

# Private config — goes to ~/.private_dotfiles
dotlayer adopt --private ~/.config/lazysql config
```

### Layer precedence across repos

Repos are processed in order. Public packages are stowed first, then private packages overlay on top. This means:

1. `~/.public_dotfiles/config/` — base config (stowed first)
2. `~/.public_dotfiles/config-linux/` — OS layer
3. `~/.public_dotfiles/config-omarchy/` — distro layer
4. `~/.private_dotfiles/config/` — private overlays (stowed after public)
5. `~/.private_dotfiles/config-mycompany/` — work group layer
6. `~/.private_dotfiles/work/` — exact group package, if configured

Each layer adds files — they never conflict because different layers use different file paths within the same directory structure.

### Keeping private dotfiles private

Your private repo doesn't need to be pushed anywhere. It works fine as a local-only git repo for tracking changes. If you do want backup:

- Push to a **private GitHub/GitLab repo**
- Use `dotlayer update` to pull both repos at once — it runs `git pull --rebase` on each repo that has a `.git` directory

## CLI reference

```
dotlayer [options] <command>

Commands:
  install     Detect system, stow all layers, install system files
  update      Pull repos, re-stow all layers
  status      Show detected OS, profile, distros, groups, and packages
  doctor      Check for broken symlinks, missing repos, missing stow
  adopt       Move config files into a stow package and restow
  version     Print version

Options:
  -c, --config PATH   Config file path
  -n, --dry-run       Run stow in no-op mode to preview changes and conflicts
  -p, --private       Use private repo (for adopt command)
  -v, --verbose       Verbose output
```

### adopt

Moves existing config files or directories into a stow package, then restows so the originals become symlinks managed by stow.

```sh
# Move a single directory
dotlayer adopt ~/.config/lazygit config

# Move multiple paths at once
dotlayer adopt ~/.config/lazygit ~/.config/lazydocker config

# Move into the private repo
dotlayer adopt --private ~/.config/lazysql config

# Preview without moving anything
dotlayer adopt --dry-run ~/.config/lazygit config
```

The last argument is always the package name. Dotlayer finds the first repo containing that package, or falls back to the first repo for new packages.

## Development

```sh
bundle exec rake test          # run tests
bundle exec standardrb         # lint
bundle exec rubycritic lib/    # code quality report
```

See [Contributing](CONTRIBUTING.md) for full setup, testing, and contribution guidelines.

## Documentation

- [Architecture](docs/architecture.md) — system design, data flow, and class responsibilities
- [Contributing](CONTRIBUTING.md) — setup, testing, and contribution guidelines

## License

[O-SaaSy](https://osaasy.dev)
