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

**Requirements:** Ruby >= 3.3, GNU Stow

## Quick start

```sh
# See what dotlayer detects on your system
dotlayer status

# Stow all matching packages
dotlayer install

# Preview what install would change (changes nothing)
dotlayer diff

# Pull latest changes and re-stow
dotlayer update

# Check for broken or dangling symlinks and missing deps
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
| **Profile** | `$DOTLAYER_PROFILE`, a `profiles: detect:` command, else DMI `chassis_type` then `hostnamectl chassis` | `desktop`, `laptop` |
| **Machine** | `$DOTLAYER_MACHINE`, configured `model:` or `detect:` rules, then `hostname -s` fallback | `t14`, `framework-desktop` |
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

#### Machine rules

A machine matches by hardware model or by a shell command. Use one of `model:` or `detect:` per machine (both, or neither, is a config error):

```yaml
machines:
  env: DOTLAYER_MACHINE
  p14s:
    model: ThinkPad P14s          # a string, or a list: the machine matches if any entry matches
  fw13:
    model: [Laptop 13, Framework]
  odd:
    detect: test -d /sys/class/foo   # shell command, exit 0 means match
```

`model:` is a case-sensitive substring match against the text dotlayer reads itself: `/sys/class/dmi/id/{product_name,product_version,board_name}` and, if present, `/proc/device-tree/model` (NULs stripped). Run `dotlayer status` to see every non-empty source and write a rule from it. Without a `profiles: detect:` command, the profile comes from DMI `chassis_type` (laptop: 8, 9, 10, 14, 30, 31, 32; desktop: 3 to 7, 15, 16, 35), then `hostnamectl chassis`, else `desktop`.

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

### Per-package target

A package entry (in `packages:`, or in a repo's `packages:`, `standalone_packages:` or `group_packages:`) is either a name or a mapping with a `target:`. The target replaces the global `target:` for that package:

```yaml
packages:
  - config
  - name: codex
    target: ~/.codex
```

`install`, `update`, `diff`, `doctor` (link checks and the dangling-link scan) and `install --backup` all use it, and `status` shows `-> <target>` when it differs. A missing target directory is created by `install`; `diff` reports it as pending. Only `name` and `target` are allowed; an unknown key or a missing name is a config error.

A layered variant that is not listed itself (for example `codex-linux`, found by the `<base>-<suffix>` convention) uses the target of its base package, `codex`. A package that is listed, such as `codex-agents` next to `codex`, uses its own target or the global one.

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
  diff        Show what install would change, without changing anything
  update      Pull repos, re-stow all layers
  status      Show detected OS, profile, distros, groups, and packages
  doctor      Check for broken/dangling symlinks, missing repos, missing stow
  adopt       Move config files into a stow package and restow
  machine     machine add <name>: add a model rule and scaffold the machine's layer
  version     Print version

Options:
  -c, --config PATH   Config file path
  -n, --dry-run       Run stow in no-op mode to preview changes and conflicts
      --backup        Install: delete identical blocking files, move different ones aside
  -y, --yes           Answer yes to install prompts (required without a terminal)
  -p, --private       Use private repo (for adopt command)
      --depth N       Max depth for doctor's dangling-link scan (default: 6)
  -v, --verbose       Verbose output
```

### install --backup

Stow refuses to link over a real file, or over a link that points outside your repos (an Omarchy theme link, say). When `install` fails with conflicts it suggests `--backup`. With it, before stowing each package, `install` looks at every file the package ships:

- a real file identical to the repo copy is deleted, and stow links it;
- anything else (a different file, or a link into some other place) is moved to `~/dotfiles-conflicts-<YYYYmmdd-HHMMSS>/`, keeping its relative path. The folder is created only when something moves, once per run.

Each action is printed, followed by a summary with the backup folder. Links into a configured repo (including through a folded parent directory) and real directories are left alone. Stow's ignore rules are not re-implemented: a simulated stow run decides which paths it would really refuse, so files stow ignores are never touched. Compare the backups with the live links, copy back what you want, and delete the folder; it may hold local secrets. With `--dry-run`, `--backup` only prints what it would do. Without `--backup`, nothing changes.

### install and system files

`install` compares each `system_files` entry with the file on disk, the same way `diff` does (destination missing, content differs, mode differs, or unreadable). Only those entries are listed, confirmed, and installed with `sudo install`. When all of them are up to date, `install` says so, asks nothing, and does not run the `after_system_files` hooks.

Pass `-y`/`--yes` to answer yes to the prompts. Without a terminal on stdin (cron, CI, a pipe) and without `--yes`, `install` prints how many system files need installing and asks you to rerun with `--yes`. That is not a failure exit. With `--dry-run` it lists the pending files and runs no sudo.

### diff

Shows what `dotlayer install` would change, without changing anything. Packages are resolved exactly like `install`, then stow runs in simulate mode (`stow -n -v`). Output is grouped per package: `LINK` and `UNLINK` operations plus `CONFLICT` entries (stow aborts the whole package on conflicts). Links that already exist are not listed. If a package ships `.stow-global-ignore` and it is not linked into `$HOME` yet, `diff` and `doctor` print a note: stow reads that file from `$HOME`, so until `install` links it the simulation uses stow's built-in ignore list and can miss conflicts (such as `.gitignore`) that `install` will hit. Linux `system_files` are listed when the destination is missing, its content differs from the source, its mode differs, or it cannot be read (no sudo is used).

```sh
dotlayer diff
```

Exit status: `0` when nothing would change, `1` when changes are pending (so it can be used in scripts).

### doctor

Checks that stow is installed, repos and packages exist, that managed config paths have no broken symlinks, and that every managed file is still a link: an app that saves by replacing the file leaves a plain file there, which `install` would refuse to overwrite. It also scans the whole target dir (default `~`) for symlinks that point into a configured repo but whose target no longer exists. The scan skips `.cache`, `node_modules`, `.git`, `.local/share/Steam` and the repos themselves. It also skips other git checkouts (any directory with a `.git`, like `~/src/*`), unless a package ships files into that path, since stow only links there in that case. It never follows directory symlinks, and stops at `--depth` levels (default 6). It only reports: each dangling link is listed with its target, followed by a suggested `rm` command.

Exit status: `0` when no issues are found, `1` otherwise.

### machine add

```
dotlayer machine add <name> [--match TEXT] [--profile laptop|desktop] [--from MACHINE] [--distro NAME] [--dry-run]
```

Adds a machine to the config file in use (`-c`, or the discovered one). It inserts a `model:` rule as the last entry of the `machines:` block, as text, so comments and layout stay as they are, and creates the layer dir in the first repo, named the way the resolver finds it: `<base>-<distro>-<profile>-<name>` (for example `config-omarchy-laptop-p14s`), or `<base>-<name>` when no distro is detected. `<base>` is `config` when it is a base package.

- `--match` is the text the model contains. Default: the longest of the model fields this machine reports (the same text `status` prints, without `board_name`). Quotes and backslashes are rejected.
- `--profile` defaults to the detected profile.
- `--from` copies that machine's layer, except `.config/hypr/monitors.lua`. Without it the layer dir is created empty.
- `--distro` is required when several distros are detected.
- It refuses a machine or layer that already exists. `--dry-run` prints the plan and writes nothing. Nothing is committed.

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
