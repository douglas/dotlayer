# Architecture

Dotlayer is a layered Ruby CLI that wraps GNU Stow. This document covers the system design, data flow, class responsibilities, and key algorithms.

## System overview

Dotlayer solves one problem: given a dotfiles repo with directories named by convention, determine which directories to stow on this machine and stow them.

The system breaks into three phases:

1. **Detect** — identify the current machine (OS, hardware profile, Linux distro)
2. **Resolve** — scan directories, match against detection, produce an ordered stow list
3. **Execute** — run GNU Stow for each resolved package

```
┌──────────┐     ┌──────────┐     ┌──────────┐
│  Detect  │────▶│ Resolve  │────▶│ Execute  │
│          │     │          │     │          │
│ OS       │     │ Scan dirs│     │ stow -d  │
│ Profile  │     │ Match    │     │ stow -R  │
│ Distros  │     │ Order    │     │ stow -D  │
└──────────┘     └──────────┘     └──────────┘
```

[Open in Excalidraw](diagrams/system-overview.excalidraw)

## Layered architecture

The codebase follows a four-layer architecture with unidirectional data flow. Lower layers never depend on higher layers.

```
┌─────────────────────────────────────────────────────┐
│                  PRESENTATION                        │
│                                                      │
│  CLI          Parse args, dispatch to commands       │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│                  APPLICATION                         │
│                                                      │
│  Commands::Status    Print detection + packages      │
│  Commands::Install   Stow + system files + hooks     │
│  Commands::Update    Pull repos + restow             │
│  Commands::Doctor    Verify health                   │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│                    DOMAIN                            │
│                                                      │
│  Detection     Value object (os, profile, distros)   │
│  Detector      Produces Detection from system state  │
│  Config        Loads YAML, provides typed accessors  │
│  Resolver      Matches dirs against Detection        │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│                 INFRASTRUCTURE                       │
│                                                      │
│  Stow          Wraps GNU Stow CLI via Open3          │
│  (Open3)       Shell command execution               │
│  (YAML)        Config file parsing                   │
│  (FileUtils)   Directory operations                  │
└─────────────────────────────────────────────────────┘
```

[Open in Excalidraw](diagrams/layers.excalidraw)

## Class responsibilities

### Detection (value object)

```ruby
Detection = Data.define(:os, :profile, :distros)
```

Immutable value object produced by `Detector`. Carries the machine identity through the system. Uses Ruby 3.2+ `Data.define` — frozen by default, structural equality, pattern matching support.

**os** — `"linux"` or `"macos"`, detected from `RbConfig::CONFIG["host_os"]`
**profile** — `"desktop"` or `"laptop"`, from `hostnamectl chassis` or `$DOTLAYER_PROFILE`
**distros** — array of detected distro names, e.g. `["omarchy"]`

### Detector

Produces a `Detection` by probing the system. Each detection axis has a fallback chain:

```
OS:       RbConfig host_os → pattern match → "unknown"
Profile:  ENV var → shell command → "desktop"
Distros:  for each configured distro, run detect command → collect successes
```

Distro detection is config-driven. Each distro entry in `dotlayer.yml` has a `detect` shell command. The command runs via `Open3.capture2e("sh", "-c", cmd)` and the distro is considered present if the exit code is 0.

### Config

Loads `dotlayer.yml` and provides typed accessors with sensible defaults. When no config file exists, defaults produce the same behavior as a vanilla dotfiles setup:

| Accessor | Default |
|----------|---------|
| `target` | `~` |
| `repos` | `[{ "path" => "~/.public_dotfiles" }]` |
| `packages` | `%w[stow bin git zsh config]` |
| `profile_detect` | `"hostnamectl chassis"` |
| `profile_env` | `"DOTLAYER_PROFILE"` |
| `distros` | `{}` |
| `system_files` | `[]` |
| `hooks` | `{}` |

### Resolver

The core algorithm. Takes a `Config` and `Detection`, scans repo directories, and returns an ordered list of `[repo_path, package_name]` tuples.

**Resolution order:**

```
1. Base packages        config, stow, bin, git, zsh
2. OS layer             config-linux
3. Distro layer         config-omarchy
4. Distro + profile     config-omarchy-desktop
```

The algorithm uses suffix matching on directory names:

```ruby
case dir
when suffix("-#{detection.os}")            # OS layer
when suffix("-#{distro}")                  # distro layer
when suffix("-#{distro}-#{detection.profile}")  # distro+profile layer
end
```

Directories are grouped by layer, then concatenated in order. This guarantees that OS packages are stowed before distro packages, and distro packages before distro+profile packages.

**Why order matters:** GNU Stow uses "tree folding" — the first package to provide a directory gets a symlink to the whole directory. Later packages that add files to the same directory cause stow to "unfold" the tree into individual file symlinks. Processing in layer order ensures the base config is established first.

### Stow

Thin wrapper around the `stow` CLI. Supports three operations:

- `stow(repo_path, package)` — create symlinks
- `restow(repo_path, package)` — delete + recreate (`stow -R`)
- `unstow(repo_path, package)` — remove symlinks (`stow -D`)

All operations go through `run_stow` which builds the command, logs it (in verbose/dry-run mode), executes via `Open3.capture2e`, and reports errors.

### Commands

Each command is a separate class with a `#run` method. Commands orchestrate domain objects:

```
Status:  Detector → Resolver → print
Install: Detector → Resolver → Stow → system files → hooks
Update:  pull repos → Detector → Resolver → Stow (restow)
Doctor:  check stow, repos, symlinks, includes
```

Commands accept `config:`, `detector:`, `dry_run:`, `verbose:` via constructor injection — making them testable without touching the filesystem.

## Data flow

A typical `dotlayer install` invocation:

```
argv = ["install"]
       │
       ▼
    CLI.run
       │ parse options, dispatch
       ▼
    Commands::Install.new(config:, dry_run:, verbose:)
       │
       ├──▶ Detector.new(config:).detect
       │       │
       │       ▼
       │    Detection(os: "linux", profile: "desktop", distros: ["omarchy"])
       │
       ├──▶ Resolver.new(config:, detection:).resolve
       │       │
       │       ▼
       │    [["~/.public_dotfiles", "stow"],
       │     ["~/.public_dotfiles", "bin"],
       │     ["~/.public_dotfiles", "git"],
       │     ["~/.public_dotfiles", "zsh"],
       │     ["~/.public_dotfiles", "config"],
       │     ["~/.public_dotfiles", "config-linux"],
       │     ["~/.public_dotfiles", "config-omarchy"],
       │     ["~/.public_dotfiles", "config-omarchy-desktop"]]
       │
       ├──▶ Stow.new(target:).stow(repo, pkg) for each package
       │       │
       │       ▼
       │    Open3: stow -d ~/.public_dotfiles -t ~ config
       │    Open3: stow -d ~/.public_dotfiles -t ~ config-linux
       │    ...
       │
       ├──▶ system files (sudo cp)
       │
       └──▶ hooks (sudo udevadm, systemctl)
```

[Open in Excalidraw](diagrams/data-flow.excalidraw)

## Stow conflict avoidance

GNU Stow cannot have two packages providing the same file path. This is a hard constraint that shapes the entire directory structure.

**Problem:** You want different Ghostty font sizes on desktop vs laptop, but the config file path is the same (`~/.config/ghostty/config`).

**Solution:** Use app-level includes to split shared config from per-machine overrides:

```
config/.config/ghostty/config          ← shared (keybindings, theme, padding)
                                         ends with: config-file = machine
config-omarchy-desktop/.config/ghostty/machine  ← font-size = 10.5
config-omarchy-laptop/.config/ghostty/machine   ← font-size = 13
```

Different filenames (`config` vs `machine`) = no Stow conflict. Ghostty's `config-file` directive loads the machine file at runtime.

For apps without include support (like Zed), the entire settings file must live in the distro+profile package — no shared version is possible.

The `doctor` command checks for missing includes (e.g., a `config-file = machine` reference with no `machine` file stowed).

## Testing strategy

Tests are organized by class, mirroring the `lib/` structure:

```
test/
  detector_test.rb    # Detection logic, env var overrides, fallbacks
  config_test.rb      # YAML parsing, defaults, repos
  resolver_test.rb    # Package resolution, layer ordering, edge cases
```

**Domain layer tests** (Detector, Config, Resolver) are thorough — these contain the core logic and are pure enough to test without mocking.

**Infrastructure tests** are lighter — `Stow` wraps a CLI tool, so integration tests against real `stow` are more valuable than unit tests with mocks.

**Test fixtures** use `Dir.mktmpdir` for filesystem state. This keeps tests fast, isolated, and cleanup-free. Config tests use inline YAML written to temp files.

External commands (like `hostnamectl chassis`) are stubbed by overriding config methods with `define_singleton_method` — no mocking framework needed.

## Future work

- `Commands::Init` — scaffold a new dotlayer repo with example packages and config
- `Commands::Private` — switch between company/work dotfiles overlays
- Shell completions (zsh, bash)
- AUR package for Arch Linux
- Homebrew tap for macOS
