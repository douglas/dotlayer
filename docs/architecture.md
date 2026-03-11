# Architecture

Dotlayer is a layered Ruby CLI that wraps GNU Stow. This document covers the system design, data flow, class responsibilities, and key algorithms.

## System overview

Dotlayer solves one problem: given a dotfiles repo with directories named by convention, determine which directories to stow on this machine and stow them.

The system breaks into three phases:

1. **Detect** — identify the current machine (OS, hardware profile, Linux distro, groups)
2. **Resolve** — scan directories, match against detection, produce an ordered stow list
3. **Execute** — run GNU Stow for each resolved package

```
┌──────────┐     ┌──────────┐     ┌──────────┐
│  Detect  │────▶│ Resolve  │────▶│ Execute  │
│          │     │          │     │          │
│ OS       │     │ Scan dirs│     │ stow -R  │
│ Profile  │     │ Match    │     │          │
│ Distros  │     │ Order    │     │          │
│ Groups   │     │          │     │          │
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
│  Commands::Adopt     Move config into stow packages  │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│                    DOMAIN                            │
│                                                      │
│  Detection     Value object (os, profile, distros,   │
│                  groups)                              │
│  Detector      Produces Detection from system state  │
│  Config        Loads YAML, provides typed accessors  │
│  Repo          Value object (path, private, packages)│
│  Resolver      Matches dirs against Detection        │
│  Output        Colored terminal output helpers       │
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
Detection = Data.define(:os, :profile, :distros, :groups)
```

Immutable value object produced by `Detector`. Carries the machine identity through the system. Uses Ruby 3.2+ `Data.define` — frozen by default, structural equality, pattern matching support.

**os** — `"linux"`, `"macos"`, or `"unknown"`, detected from `RbConfig::CONFIG["host_os"]`
**profile** — `"desktop"` or `"laptop"`, from `hostnamectl chassis` or `$DOTLAYER_PROFILE`
**distros** — array of detected distro names, e.g. `["omarchy"]`
**groups** — array of detected group names, e.g. `["mycompany"]`

### Repo (value object)

```ruby
Repo = Data.define(:path, :private, :packages)
```

Immutable value object representing a dotfiles repository. `private` marks it for sensitive configs. `packages` optionally overrides the global package list for this repo.

### Detector

Produces a `Detection` by probing the system. Each detection axis has a fallback chain:

```
OS:       RbConfig host_os → pattern match → "unknown"
Profile:  ENV var → shell command → "desktop"
Distros:  for each configured distro, run detect command → collect successes
Groups:   for each configured group, run detect command → collect successes
```

Distro and group detection is config-driven. Each entry in `dotlayer.yml` has a `detect` shell command. The command runs via `Open3.capture2e("sh", "-c", cmd)` and the entry is considered present if the exit code is 0.

Guard clause: commands must be a non-empty `String`; nil, empty, and non-string values are silently skipped.

### Config

Loads `dotlayer.yml` and provides typed accessors with sensible defaults. Config is discovered automatically from standard paths, or passed explicitly via `-c` flag.

When no config file exists, defaults produce the same behavior as a vanilla dotfiles setup:

| Accessor | Default |
|----------|---------|
| `target` | `~` |
| `repos` | `[Repo(path: "~/.public_dotfiles")]` |
| `packages` | `%w[stow bin git zsh config]` |
| `profile_detect` | `"hostnamectl chassis"` |
| `profile_env` | `"DOTLAYER_PROFILE"` |
| `distros` | `{}` |
| `groups` | `{}` |
| `system_files` | `[]` |
| `hooks` | `{}` |

Error handling: invalid YAML and non-hash YAML both `abort` with a descriptive message. Repos with nil or empty paths are filtered out.

### Output (module)

Mixin providing colored terminal output. Included by all command classes.

Methods: `heading`, `ok`, `error`, `warning`, `info` (print with newline), `green`, `red`, `yellow`, `bold` (return colored strings), `restow_package` (formatted stow status with success/failure/dry-run branching).

### Resolver

The core algorithm. Takes a `Config` and `Detection`, scans repo directories, and returns an ordered list of `[repo_path, package_name]` tuples.

**Resolution strategies:**

- **Layered repos** — repos where at least one base package directory exists. Resolves layers in order, then appends standalone directories alphabetically.
- **All-packages repos** — repos where no base package directories exist. Stows all top-level directories alphabetically.

Per-repo `packages` override the global package list for that repo.

**Layer resolution order:**

```
1. Base packages        config, stow, bin, git, zsh
2. OS layer             config-linux
3. Distro layer         config-omarchy
4. Distro + profile     config-omarchy-desktop
5. Group layer          config-mycompany
6. Standalone dirs      claude, scripts (alphabetical)
```

The algorithm uses suffix matching on directory names:

```ruby
case dir
when suffix("-#{detection.os}")                       # OS layer
when suffix("-#{distro}")                             # distro layer
when suffix("-#{distro}-#{detection.profile}")        # distro+profile layer
when suffix("-#{group}")                              # group layer
end
```

Directories are grouped by layer, then concatenated in order. This guarantees that OS packages are stowed before distro packages, distro before distro+profile, and distro+profile before groups.

**Layer variant detection:** A directory like `config-fedora` is recognized as a layer variant of `config` by checking `dir.start_with?("#{pkg}-")`. This prevents standalone resolution from picking it up. Importantly, `configure` is NOT a variant of `config` — the `-` separator is required.

**Why order matters:** GNU Stow uses "tree folding" — the first package to provide a directory gets a symlink to the whole directory. Later packages that add files to the same directory cause stow to "unfold" the tree into individual file symlinks. Processing in layer order ensures the base config is established first.

### Stow

Thin wrapper around the `stow` CLI. Provides a single operation:

- `restow(repo_path, package)` — delete + recreate symlinks (`stow -R`)

Returns `true` on success, `false` on failure. On failure, `last_error` contains the error output. On success, `last_error` is cleared to `nil`.

Supports `dry_run:` (prints command to stderr, returns true without executing) and `verbose:` (adds `-v` flag and prints command to stderr).

Catches `Errno::ENOENT` when the `stow` binary is not installed and sets a descriptive error message.

### Commands

Each command is a separate class with a `#run` method. Commands orchestrate domain objects:

```
Status:  Detector → Resolver → print detection + packages
Install: Detector → Resolver → Stow → system files → hooks
Update:  pull repos (git pull --rebase) → Detector → Resolver → Stow (restow)
Doctor:  check stow installed, repos exist, packages exist, broken symlinks
Adopt:   find repo → move paths into package → Stow (restow)
```

Commands accept `config:`, `detector:`, `dry_run:`, `verbose:` via constructor injection — making them testable without touching the filesystem.

**Install** also handles system files (Linux only, requires sudo with user confirmation) and post-install hooks (also require user confirmation). Both are skipped in dry-run mode.

**Adopt** finds the appropriate repo (private if `-p` flag, else first repo with the package, else first repo), moves each path into the package preserving the directory structure relative to target, then restows.

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
       │    Detection(os: "linux", profile: "desktop",
       │             distros: ["omarchy"], groups: ["mycompany"])
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
       │     ["~/.public_dotfiles", "config-omarchy-desktop"],
       │     ["~/.public_dotfiles", "config-mycompany"]]
       │
       ├──▶ Stow.new(target:).restow(repo, pkg) for each package
       │       │
       │       ▼
       │    Open3: stow -R -d ~/.public_dotfiles -t ~ config
       │    Open3: stow -R -d ~/.public_dotfiles -t ~ config-linux
       │    ...
       │
       ├──▶ system files (sudo cp, with user confirmation)
       │
       └──▶ hooks (with user confirmation)
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

## Testing strategy

Tests are organized by class, mirroring the `lib/` structure. All test files live flat in `test/` (not nested under `test/commands/`).

```
test/
  config_test.rb      # YAML parsing, defaults, repos, error handling
  detector_test.rb    # Detection logic, env var overrides, fallbacks, guard clauses
  resolver_test.rb    # Package resolution, layer ordering, multi-repo, edge cases
  cli_test.rb         # Argument parsing, command routing, version flag
  adopt_test.rb       # File/directory moves, dry-run, private repo, errors
  doctor_test.rb      # Health checks: repos, symlinks, stow, packages
  install_test.rb     # Stow packages, system files, hooks, user confirmation
  update_test.rb      # Pull repos + restow, dry-run, error handling
  status_test.rb      # Detection display, package listing
  output_test.rb      # restow_package branching (success/failure/dry-run)
  stow_test.rb        # Symlink creation, dry-run, verbose, error reporting
```

**Domain layer tests** (Detector, Config, Resolver) are thorough — these contain the core logic and are pure enough to test without mocking.

**Command tests** exercise the full command flow through real domain objects, using `stub_detector` and `stub_config` helpers to control detection without mocking internals.

**Infrastructure tests** are lighter — `Stow` wraps a CLI tool, so integration tests against real `stow` are more valuable than unit tests with mocks.

**Test fixtures** use `Dir.mktmpdir` for filesystem state. This keeps tests fast, isolated, and cleanup-free. Config tests use inline YAML written to temp files.

**Stubbing:** External commands are stubbed by overriding config methods or using `define_singleton_method`. `minitest/mock` is not available (Ruby 4.0 bundled gem issue), so all stubs use this pattern. Shared helpers in `TestConfigHelper` (`build_detection`, `stub_detector`, `stub_config`, `build_repo`) eliminate boilerplate.

**Philosophy:** Tests cover project behavior only — never Ruby language features. See the `minitest-style` Claude skill for the full rationale and anti-pattern list.

## Future work

- `Commands::Init` — scaffold a new dotlayer repo with example packages and config
- Shell completions (zsh, bash)
- AUR package for Arch Linux
- Homebrew tap for macOS
