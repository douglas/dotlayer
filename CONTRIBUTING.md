# Contributing to dotlayer

## Setup

Clone the repo and install dependencies:

```sh
git clone https://github.com/douglas/dotlayer.git
cd dotlayer
```

### Ruby version

Dotlayer uses [mise](https://mise.jdx.dev/) for Ruby version management. The required version is declared in `.mise.toml`:

```sh
mise install    # installs the correct Ruby version
mise trust      # trust the project config (first time only)
```

If you don't use mise, any Ruby >= 3.2 will work.

### Dependencies

Install gems:

```sh
bundle install
```

Dotlayer has **zero runtime dependencies** — everything uses Ruby stdlib. Dev dependencies are `minitest`, `rake`, and `standard` (linter).

## Running tests

```sh
bundle exec rake test
```

Or run a single test file:

```sh
bundle exec ruby -Ilib:test test/resolver_test.rb
```

Or run the full suite directly:

```sh
mise x -- bundle exec ruby -Ilib -Itest -e "Dir.glob('test/**/*_test.rb').each { |f| require_relative f }"
```

Tests use `Dir.mktmpdir` for filesystem fixtures — no external services or complex setup needed.

## Linting

```sh
bundle exec standardrb
```

To auto-fix violations:

```sh
bundle exec standardrb --fix
```

We use [Standard](https://github.com/standardrb/standard) (based on RuboCop) with zero configuration. Run it before committing.

### Test suite overview

94 tests, 262 assertions. Suite runs in ~1 second.

| File | Tests | What it covers |
|------|-------|----------------|
| `config_test.rb` | 10 | YAML loading, defaults, repos, packages, distros, groups, hooks, system files, error handling |
| `detector_test.rb` | 10 | OS detection, profile from env/command/fallback, distro/group detection, invalid inputs |
| `resolver_test.rb` | 15 | Base packages, OS/distro/group layers, layer ordering, per-repo packages, standalone dirs, edge cases |
| `cli_test.rb` | 7 | Argument parsing, command routing, version flag, dry-run forwarding, adopt validation |
| `adopt_test.rb` | 11 | File/directory moves, dry-run, private repo, multiple paths, error conditions |
| `doctor_test.rb` | 6 | Missing repos, broken symlinks, missing stow, missing packages, issue counting |
| `install_test.rb` | 10 | Stow packages, dry-run, system files, hooks, macOS skip, user confirmation |
| `update_test.rb` | 4 | Pull + restow, dry-run, skip non-git repos, pull failure handling |
| `status_test.rb` | 4 | Detection display, package listing, multi-repo, empty distros/groups |
| `output_test.rb` | 4 | `restow_package` output: success, failure, dry-run, custom verb |
| `stow_test.rb` | 7 | Symlink creation, dry-run, error reporting, verbose output, missing stow binary |

### Test helpers

`test/test_helper.rb` provides `TestConfigHelper` with shared helpers to reduce boilerplate:

- `stub_config(target:, repos:, packages:, **overrides)` — creates a Config with stubbed methods
- `build_repo(path:, private:, packages:)` — builds a Repo data object
- `build_detection(os:, profile:, distros:, groups:)` — builds a Detection with sensible defaults
- `stub_detector(detection)` — creates a mock Detector that returns a fixed Detection

## Project structure

```
exe/dotlayer              # CLI entry point
lib/
  dotlayer.rb             # Module root, autoloads, version
  dotlayer/
    cli.rb                # Argument parsing, command dispatch
    config.rb             # YAML config loader with defaults (also defines Repo)
    detector.rb           # OS/profile/distro/group detection (also defines Detection)
    output.rb             # Colored terminal output helpers
    resolver.rb           # Package resolution algorithm
    stow.rb               # GNU Stow wrapper
    commands/
      adopt.rb            # dotlayer adopt
      doctor.rb           # dotlayer doctor
      install.rb          # dotlayer install
      status.rb           # dotlayer status
      update.rb           # dotlayer update
test/
  test_helper.rb          # Minitest setup + TestConfigHelper
  adopt_test.rb           # Adopt command tests
  cli_test.rb             # CLI routing tests
  config_test.rb          # Config loading and defaults
  detector_test.rb        # Detection logic
  doctor_test.rb          # Doctor command tests
  install_test.rb         # Install command tests
  output_test.rb          # Output formatting tests
  resolver_test.rb        # Package resolution
  status_test.rb          # Status command tests
  stow_test.rb            # Stow wrapper tests
  update_test.rb          # Update command tests
  fixtures/
    dotlayer.yml          # Example config for reference
```

## Architecture

See [docs/architecture.md](docs/architecture.md) for the full system design.

The short version: data flows in one direction through four layers.

```
CLI (presentation) → Commands (application) → Detector/Resolver/Config (domain) → Stow (infrastructure)
```

Lower layers never depend on higher layers. `Detector`, `Config`, and `Resolver` are pure logic with no side effects — they're the easiest to test and modify.

## Code conventions

### Style

- [Standard](https://github.com/standardrb/standard) for linting — run `bundle exec standardrb` before committing
- Prefer stdlib over gems. Adding a runtime dependency needs a strong justification
- Use `Data.define` for immutable value objects (Ruby 3.2+)
- Use `autoload` for lazy loading (no eager requires)

### Testing

- Every new class gets a corresponding `*_test.rb` file in `test/` (flat, not nested)
- Use `Dir.mktmpdir` for filesystem tests — clean up in `teardown` or `ensure`
- Use `TestConfigHelper` methods (`build_detection`, `stub_detector`, `stub_config`) instead of raw constructors
- Stub external commands by overriding methods with `define_singleton_method` — `minitest/mock` is not available
- Test project behavior, not Ruby language features (see `minitest-style` skill for details)
- Domain tests (Detector, Config, Resolver) should be thorough; command tests can be lighter

### Commits

- One logical change per commit
- Imperative mood in commit messages ("Add doctor command", not "Added doctor command")

## Adding a new command

1. Create `lib/dotlayer/commands/foo.rb` with a class `Dotlayer::Commands::Foo` that has a `#run` method
2. Add `autoload :Foo, "dotlayer/commands/foo"` to `lib/dotlayer.rb` inside the `Commands` module
3. Add the command to the `case` statement in `lib/dotlayer/cli.rb`
4. Add tests in `test/foo_test.rb`
5. Update the usage text in `CLI#print_usage`

## Adding a new detection method

Detection happens in `Detector`. Distro and group detection is config-driven — users add detect commands to `dotlayer.yml` under `distros:` or `groups:`. If you need a new built-in detection axis (beyond OS, profile, distros, groups), modify `Detection = Data.define(...)` and update `Resolver` to match against it.

## Releasing

```sh
# Update VERSION in lib/dotlayer.rb
# Commit and tag
git tag v0.2.1
gem build dotlayer.gemspec
gem push dotlayer-0.2.1.gem
```
