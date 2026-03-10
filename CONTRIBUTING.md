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

Dotlayer has **zero runtime dependencies** — everything uses Ruby stdlib. The only dev dependencies are `minitest` and `rake`.

## Running tests

```sh
bundle exec rake test
```

Or run a single test file:

```sh
bundle exec ruby -Ilib:test test/resolver_test.rb
```

Tests use `Dir.mktmpdir` for filesystem fixtures — no external services or complex setup needed.

## Project structure

```
exe/dotlayer              # CLI entry point
lib/
  dotlayer.rb             # Module root, autoloads, version
  dotlayer/
    cli.rb                # Argument parsing, command dispatch
    config.rb             # YAML config loader with defaults
    detector.rb           # OS/profile/distro detection
    resolver.rb           # Package resolution algorithm
    stow.rb               # GNU Stow wrapper
    commands/
      status.rb           # dotlayer status
      install.rb          # dotlayer install
      update.rb           # dotlayer update
      doctor.rb           # dotlayer doctor
test/
  test_helper.rb          # Minitest setup
  config_test.rb          # Config loading and defaults
  detector_test.rb        # Detection logic
  resolver_test.rb        # Package resolution
  fixtures/
    dotlayer.yml          # Example config for tests
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

- No linter enforced yet — just keep it consistent with existing code
- Prefer stdlib over gems. Adding a runtime dependency needs a strong justification
- Use `Data.define` for immutable value objects (Ruby 3.2+)
- Use `autoload` for lazy loading (no eager requires)

### Testing

- Every new class gets a corresponding `*_test.rb` file
- Use `Dir.mktmpdir` for filesystem tests — always clean up in `teardown`
- Stub external commands by overriding methods with `define_singleton_method` — no mocking framework needed
- Test the domain layer (Detector, Config, Resolver) thoroughly; commands can have lighter coverage

### Commits

- One logical change per commit
- Imperative mood in commit messages ("Add doctor command", not "Added doctor command")

## Adding a new command

1. Create `lib/dotlayer/commands/foo.rb` with a class `Dotlayer::Commands::Foo` that has a `#run` method
2. Add `autoload :Foo, "dotlayer/commands/foo"` to `lib/dotlayer.rb` inside the `Commands` module
3. Add the command to the `case` statement in `lib/dotlayer/cli.rb`
4. Add tests in `test/commands/foo_test.rb`
5. Update the usage text in `CLI#print_usage`

## Adding a new detection method

Detection happens in `Detector`. Distro detection is config-driven — users add detect commands to `dotlayer.yml` under `distros:`. If you need a new built-in detection axis (beyond OS, profile, distros), modify `Detection = Data.define(...)` and update `Resolver` to match against it.

## Releasing

```sh
# Update version in lib/dotlayer.rb
# Commit and tag
git tag v0.1.0
gem build dotlayer.gemspec
gem push dotlayer-0.1.0.gem
```
