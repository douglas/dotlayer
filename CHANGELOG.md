# Changelog

All notable changes to dotlayer. Versions follow [Semantic Versioning](https://semver.org/).

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
