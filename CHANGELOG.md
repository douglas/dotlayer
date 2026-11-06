# Changelog

All notable changes to dotlayer. Versions follow [Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- Machines can match by hardware model instead of a shell command:
  `model: ThinkPad P14s` (or a list). dotlayer reads
  `/sys/class/dmi/id/{product_name,product_version,board_name}` and
  `/proc/device-tree/model` itself and matches case-sensitive substrings. A
  machine has `detect:` or `model:`, not both. `status` prints each model text
  it read, to write rules from.
- `dotlayer machine add <name> [--match TEXT] [--profile P] [--from MACHINE]
  [--distro D] [--dry-run]` writes a `model:` rule into the config's
  `machines:` block, keeping the rest of the file as text, and scaffolds the
  machine's layer dir in the first repo, copied from `--from` without
  `hypr/monitors.lua`.
- Config discovery also checks `$DOTLAYER_CONFIG` first, and the stowed file's
  home in the repos (`~/.private_dotfiles/config/.config/dotlayer/dotlayer.yml`,
  then `~/.public_dotfiles/...`) when `~/.config/dotlayer/dotlayer.yml` does not
  exist yet. `status` shows which file was used; `-v` prints it to stderr.
- Without `profiles: detect:`, the profile comes from DMI `chassis_type`, then
  `hostnamectl chassis`, else `desktop`.

- Per-package target: a package entry in `packages:` (top-level or per repo),
  `standalone_packages:` or `group_packages:` may be `{name: codex, target:
  ~/.codex}` instead of a name. The target replaces the global `target:` for
  stow, `diff`, `doctor` (link checks and the dangling-link scan), `status`
  (shown when it differs), and `--backup`. A layered variant that is not listed
  itself, such as `codex-linux`, uses its base package's target. String entries
  work as before; an unknown key or a missing name is a config error.
- `install` creates a missing package target directory; `diff` reports it.
- `install --backup` clears what stow would refuse to overwrite before it
  stows each package. A real file identical to the repo copy is deleted; a
  different file, or a link pointing outside the configured repos, is moved to
  `~/dotfiles-conflicts-<timestamp>/` with its relative path. Each action and a
  summary are printed. `--dry-run` only reports. Stow's own ignore rules still
  apply, because a stow simulation decides which paths it would refuse.
- `install` suggests `--backup` when a package fails with conflicts.
- `install -y`/`--yes` answers yes to the system-file and hook prompts.

### Changed

- `install` only lists, confirms, and installs system files that are pending,
  using the same check as `diff` (missing, content, mode, unreadable). When all
  are up to date it says so, skips the prompt, and does not run the
  `after_system_files` hooks.
- Without a terminal and without `--yes`, `install` reports how many system
  files need installing and asks you to rerun with `--yes`, instead of reading
  EOF and printing "Skipped." This is not a failure exit.

### Fixed

- `diff` and `doctor` could report no conflict for a file that `install` then
  refused to overwrite, such as `.config/nvim/.gitignore`. Stow reads its
  global ignore list from `$HOME/.stow-global-ignore`, and until `install`
  links it, a simulation uses stow's built-in list, which ignores `.gitignore`.
  Both commands now print a note when a package ships that file and it is not
  linked yet.

## 0.3.2 — 2026-11-05

### Added

- `doctor` reports managed files that are no longer links. Tools that save by
  writing a temp file and renaming it, or with `sed -i`, replace a stowed link
  with a plain file, and changes in the repo stop reaching the machine. Before,
  only `install` noticed, by failing with conflicts. The check asks Stow in
  simulate mode, so it follows Stow's own ignore rules.

## 0.3.1 — 2026-11-05

First RubyGems release since 0.2.2: it includes everything listed under 0.3.0,
which was tagged but never published.

### Changed

- `doctor`'s dangling-link scan skips other git checkouts under the target
  (any directory with a `.git`, like `~/src/*`), unless a package ships files
  into that path. Stow only links into a checkout in that case, and checkouts
  are most of the directories in a typical home dir: `doctor` went from 5.9s to
  0.9s on a development machine.

## 0.3.0 — 2026-11-04 (tagged, not published)

### Added

- Machine layers: `config-<machine>`, `config-<os>-<machine>`,
  `config-<distro>-<machine>` and `config-<distro>-<profile>-<machine>`. The
  machine tag comes from `$DOTLAYER_MACHINE`, then `machines.<tag>.detect`
  commands in `dotlayer.yml`, then `hostname -s`.
- `dotlayer diff`: shows what `install` would link, unlink or conflict on, and
  which system files would change, without changing anything.
- `doctor` scans the whole target dir for links into a configured repo whose
  destination no longer exists, and prints an `rm` command for them. It never
  deletes anything. `--depth N` limits the scan (default 6).

### Changed

- Stow runs with `--no-folding`: every file gets its own link, never a link to
  a whole directory.
- `doctor`'s broken-symlink check covers only managed `.config` and `.local`
  paths, and the dangling-link scan skips `.local/state` (app backups).
- System files: parent directories are created when missing, and a failed copy
  fails the install.
- Requires Ruby 3.3 or newer; CI tests Ruby 3.3 through 4.0 and installs Stow.

### Fixed

- Profile detection no longer crashes on macOS, where `hostnamectl` doesn't
  exist.
- `diff` conflict handling works with older Stow versions.

## 0.2.2 and earlier

See the [git tags](https://github.com/douglas/dotlayer/tags).
