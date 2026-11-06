require "test_helper"

class InstallTest < Minitest::Test
  include TestConfigHelper

  def setup
    @tmpdir = Dir.mktmpdir
    @target = File.join(@tmpdir, "home")
    @repo = File.join(@tmpdir, "repo")
    FileUtils.mkdir_p([@target, File.join(@repo, "config", ".config", "test")])
    File.write(File.join(@repo, "config", ".config", "test", "config.yml"), "hello")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_dry_run_does_not_create_symlinks
    config = stub_config(
      target: @target,
      repos: [build_repo(path: @repo)],
      packages: %w[config]
    )

    output = capture_io {
      Dotlayer::Commands::Install.new(config:, detector: stub_detector, dry_run: true).run
    }.first

    assert_match(/dry-run/, output)
    assert_match(/1 package/, output)
    refute File.exist?(File.join(@target, ".config", "test"))
  end

  def test_stows_packages
    config = stub_config(
      target: @target,
      repos: [build_repo(path: @repo)],
      packages: %w[config]
    )

    output = capture_io {
      Dotlayer::Commands::Install.new(config:, detector: stub_detector).run
    }.first

    assert_match(/Stowing.*config/, output)
    assert_match(/1 package/, output)
    assert File.directory?(File.join(@target, ".config"))
    assert File.directory?(File.join(@target, ".config", "test"))
    assert File.symlink?(File.join(@target, ".config", "test", "config.yml")),
      "stow should create file symlinks in target"
  end

  def test_stow_failure_aborts_before_system_files
    File.write(File.join(@target, ".config"), "conflict")
    config = stub_config(
      target: @target,
      repos: [build_repo(path: @repo)],
      packages: %w[config],
      system_files: [{"source" => "config/etc/test.conf", "dest" => File.join(@tmpdir, "test.conf")}]
    )

    assert_raises(SystemExit) do
      capture_io {
        Dotlayer::Commands::Install.new(config:, detector: stub_detector).run
      }
    end
  end

  def test_conflict_failure_hints_at_backup
    live = File.join(@target, ".config", "test", "config.yml")
    FileUtils.mkdir_p(File.dirname(live))
    File.write(live, "mine")

    output = capture_io {
      assert_raises(SystemExit) { Dotlayer::Commands::Install.new(config: package_config, detector: stub_detector).run }
    }.first

    assert_match(/Rerun with --backup/, output)
  end

  def test_backup_clears_conflicts_then_stows
    live = File.join(@target, ".config", "test", "config.yml")
    FileUtils.mkdir_p(File.dirname(live))
    File.write(live, "mine")

    output = capture_io {
      Dotlayer::Commands::Install.new(config: package_config, detector: stub_detector, backup: true).run
    }.first

    assert File.symlink?(live)
    assert_match(/moving to backup: \.config\/test\/config\.yml/, output)
    assert_equal "mine", File.read(Dir.glob(File.join(@target, "dotfiles-conflicts-*", ".config", "test", "config.yml")).first)
    refute_match(/Rerun with --backup/, output)
  end

  def test_backup_dry_run_reports_without_failing_or_changing_anything
    live = File.join(@target, ".config", "test", "config.yml")
    FileUtils.mkdir_p(File.dirname(live))
    File.write(live, "mine")

    output = capture_io {
      Dotlayer::Commands::Install.new(config: package_config, detector: stub_detector, dry_run: true, backup: true).run
    }.first

    assert_match(/would move to backup/, output)
    assert_equal "mine", File.read(live)
    assert_empty Dir.glob(File.join(@target, "dotfiles-conflicts-*"))
  end

  def test_package_with_target_installs_there
    codex_target = File.join(@tmpdir, "codex-home")
    FileUtils.mkdir_p(File.join(@repo, "codex"))
    File.write(File.join(@repo, "codex", "config.toml"), "x")
    config = stub_config(
      target: @target,
      repos: [build_repo(path: @repo, packages: %w[config codex], targets: {"codex" => codex_target})]
    )

    output = capture_io { Dotlayer::Commands::Install.new(config:, detector: stub_detector).run }.first

    assert File.symlink?(File.join(codex_target, "config.toml"))
    refute File.exist?(File.join(@target, "config.toml"))
    assert File.symlink?(File.join(@target, ".config", "test", "config.yml"))
    assert_match(/2 package/, output)
  end

  def test_backup_uses_the_package_target
    codex_target = File.join(@tmpdir, "codex-home")
    FileUtils.mkdir_p([File.join(@repo, "codex"), codex_target])
    File.write(File.join(@repo, "codex", "config.toml"), "repo")
    File.write(File.join(codex_target, "config.toml"), "mine")
    config = stub_config(
      target: @target,
      repos: [build_repo(path: @repo, packages: %w[codex], targets: {"codex" => codex_target})]
    )

    capture_io { Dotlayer::Commands::Install.new(config:, detector: stub_detector, backup: true).run }

    assert File.symlink?(File.join(codex_target, "config.toml"))
    moved = Dir.glob(File.join(@target, "dotfiles-conflicts-*", "**", "config.toml"))
    assert_equal ["mine"], moved.map { |f| File.read(f) }
  end

  def test_quiet_prints_nothing_on_success
    output = capture_io {
      Dotlayer::Commands::Install.new(config: package_config, detector: stub_detector, quiet: true).run
    }.first

    assert_empty output
    assert File.symlink?(File.join(@target, ".config", "test", "config.yml"))
  end

  def test_quiet_still_says_when_system_files_need_yes
    config = system_files_config(changed: "new")

    output = run_install(config, commands_run: [], stdin: StringIO.new(""), quiet: true)

    assert_equal 1, output.lines.size
    assert_match(/1 system file\(s\) need installing.*--yes/, output)
  end

  def test_quiet_prints_everything_on_failure
    File.write(File.join(@target, ".config"), "conflict")

    output = capture_io {
      assert_raises(SystemExit) {
        Dotlayer::Commands::Install.new(config: package_config, detector: stub_detector, quiet: true).run
      }
    }.first

    assert_match(/Installing dotfiles/, output)
    assert_match(/failed/, output)
  end

  def test_skips_system_files_when_no_repos
    config = stub_config(
      target: @target,
      repos: [],
      packages: %w[config],
      system_files: [{"source" => "foo", "dest" => "/tmp/bar"}]
    )

    output = capture_io {
      Dotlayer::Commands::Install.new(config:, detector: stub_detector).run
    }.first

    assert_match(/Skipping system files/, output)
  end

  def test_system_files_dry_run_prints_dry_run
    system_file = File.join(@repo, "config", "etc", "test.conf")
    FileUtils.mkdir_p(File.dirname(system_file))
    File.write(system_file, "content")

    config = stub_config(
      target: @target,
      repos: [build_repo(path: @repo)],
      packages: %w[config],
      system_files: [{"source" => "config/etc/test.conf", "dest" => File.join(@tmpdir, "test.conf")}],
      hooks: {}
    )

    output = capture_io {
      Dotlayer::Commands::Install.new(config:, detector: stub_detector, dry_run: true).run
    }.first

    assert_match(/System files/, output)
    assert_match(/dry-run/, output)
    refute File.exist?(File.join(@tmpdir, "test.conf"))
  end

  def test_system_files_stdin_reject_skips
    config = stub_config(
      target: @target,
      repos: [build_repo(path: @repo)],
      packages: %w[config],
      system_files: [{"source" => "config/etc/test.conf", "dest" => File.join(@tmpdir, "test.conf")}],
      hooks: {}
    )

    original_stdin = $stdin
    $stdin = tty_stdin("n\n")
    output = capture_io {
      Dotlayer::Commands::Install.new(config:, detector: stub_detector).run
    }.first
    $stdin = original_stdin

    assert_match(/Skipped/, output)
  ensure
    $stdin = original_stdin
  end

  def test_macos_skips_system_files
    config = stub_config(
      target: @target,
      repos: [build_repo(path: @repo)],
      packages: %w[config],
      system_files: [{"source" => "foo", "dest" => "/tmp/bar"}],
      hooks: {}
    )
    detection = build_detection(os: "macos")

    output = capture_io {
      Dotlayer::Commands::Install.new(config:, detector: stub_detector(detection)).run
    }.first

    refute_match(/System files/, output)
  end

  def test_hooks_dry_run_prints_dry_run
    system_file = File.join(@repo, "config", "etc", "test.conf")
    FileUtils.mkdir_p(File.dirname(system_file))
    File.write(system_file, "content")

    config = stub_config(
      target: @target,
      repos: [build_repo(path: @repo)],
      packages: %w[config],
      system_files: [{"source" => "config/etc/test.conf", "dest" => File.join(@tmpdir, "hook_test")}],
      hooks: {"after_system_files" => ["echo hook_ran"]}
    )

    output = capture_io {
      Dotlayer::Commands::Install.new(config:, detector: stub_detector, dry_run: true).run
    }.first

    assert_match(/after_system_files hooks/, output)
    assert_match(/echo hook_ran.*dry-run/, output)
  end

  def test_hooks_stdin_reject_skips
    system_file = File.join(@repo, "config", "etc", "test.conf")
    FileUtils.mkdir_p(File.dirname(system_file))
    File.write(system_file, "content")

    config = stub_config(
      target: @target,
      repos: [build_repo(path: @repo)],
      packages: %w[config],
      system_files: [{"source" => "config/etc/test.conf", "dest" => File.join(@tmpdir, "hook_test")}],
      hooks: {"after_system_files" => ["echo hook_ran"]}
    )

    # First "y" accepts system files install, second "n" rejects hooks
    original_stdin = $stdin
    $stdin = tty_stdin("y\nn\n")
    output = capture_io {
      # stub system() to avoid actual sudo
      install = Dotlayer::Commands::Install.new(config:, detector: stub_detector)
      install.define_singleton_method(:system) { |*_args| true }
      install.run
    }.first
    $stdin = original_stdin

    assert_match(/after_system_files hooks/, output)
    assert_match(/Skipped/, output)
  ensure
    $stdin = original_stdin
  end

  def test_hooks_stdin_accept_runs_hooks
    system_file = File.join(@repo, "config", "etc", "test.conf")
    FileUtils.mkdir_p(File.dirname(system_file))
    File.write(system_file, "content")

    config = stub_config(
      target: @target,
      repos: [build_repo(path: @repo)],
      packages: %w[config],
      system_files: [{"source" => "config/etc/test.conf", "dest" => File.join(@tmpdir, "hook_test")}],
      hooks: {"after_system_files" => ["echo hook_ran"]}
    )

    # "y" accepts system files, "y" accepts hooks
    original_stdin = $stdin
    $stdin = tty_stdin("y\ny\n")
    commands_run = []
    output = capture_io {
      install = Dotlayer::Commands::Install.new(config:, detector: stub_detector)
      install.define_singleton_method(:system) { |*args|
        commands_run << args
        true
      }
      install.run
    }.first
    $stdin = original_stdin

    assert_match(/echo hook_ran/, output)
    assert_match(/ok/, output)
    assert commands_run.any? { |args| args == ["echo hook_ran"] }, "hook command should have been executed"
  ensure
    $stdin = original_stdin
  end

  def test_system_files_use_install_with_parent_dirs_and_default_mode
    system_file = File.join(@repo, "config", "etc", "test.conf")
    FileUtils.mkdir_p(File.dirname(system_file))
    File.write(system_file, "content")

    config = stub_config(
      target: @target,
      repos: [build_repo(path: @repo)],
      packages: %w[config],
      system_files: [{"source" => "config/etc/test.conf", "dest" => File.join(@tmpdir, "new-dir", "test.conf")}]
    )

    original_stdin = $stdin
    $stdin = tty_stdin("y\n")
    commands_run = []
    capture_io {
      install = Dotlayer::Commands::Install.new(config:, detector: stub_detector)
      install.define_singleton_method(:system) { |*args|
        commands_run << args
        true
      }
      install.run
    }

    assert_includes commands_run, ["sudo", "install", "-D", "-m", "0644", system_file, File.join(@tmpdir, "new-dir", "test.conf")]
  ensure
    $stdin = original_stdin
  end

  def test_failed_system_file_exits_nonzero
    system_file = File.join(@repo, "config", "etc", "test.conf")
    FileUtils.mkdir_p(File.dirname(system_file))
    File.write(system_file, "content")

    config = stub_config(
      target: @target,
      repos: [build_repo(path: @repo)],
      packages: %w[config],
      system_files: [{"source" => "config/etc/test.conf", "dest" => File.join(@tmpdir, "test.conf")}]
    )

    original_stdin = $stdin
    $stdin = tty_stdin("y\n")
    assert_raises(SystemExit) do
      capture_io {
        install = Dotlayer::Commands::Install.new(config:, detector: stub_detector)
        install.define_singleton_method(:system) { |*_args| false }
        install.run
      }
    end
  ensure
    $stdin = original_stdin
  end

  def test_system_files_up_to_date_skips_prompt_install_and_hooks
    config = system_files_config(same: "a")
    commands_run = []

    output = run_install(config, commands_run:, stdin: tty_stdin(""))

    assert_match(/System files are up to date/, output)
    refute_match(/Continue\?/, output)
    refute_match(/hooks/, output)
    assert_empty commands_run
  end

  def test_only_pending_system_files_are_listed_and_installed
    config = system_files_config(same: "a", changed: "new")
    File.write(File.join(@tmpdir, "changed.conf"), "old")
    commands_run = []

    output = run_install(config, commands_run:, stdin: tty_stdin("y\ny\n"))

    assert_match(/changed\.conf \(content differs\)/, output)
    refute_match(/same\.conf/, output)
    installs = commands_run.select { |args| args.first == "sudo" }
    assert_equal 1, installs.size
    assert_equal File.join(@tmpdir, "changed.conf"), installs.first.last
    assert_includes commands_run, ["echo hook_ran"]
  end

  def test_system_files_without_terminal_or_yes_asks_for_yes_and_does_not_fail
    config = system_files_config(changed: "new")
    commands_run = []

    output = run_install(config, commands_run:, stdin: StringIO.new(""))

    assert_match(/1 system file\(s\) need installing.*--yes/, output)
    refute_match(/Skipped/, output)
    refute_match(/hooks/, output)
    assert_empty commands_run
  end

  def test_yes_installs_pending_system_files_and_runs_hooks_without_input
    config = system_files_config(changed: "new")
    commands_run = []

    output = run_install(config, commands_run:, stdin: StringIO.new(""), yes: true)

    refute_match(/Skipped/, output)
    assert_equal 1, commands_run.count { |args| args.first == "sudo" }
    assert_includes commands_run, ["echo hook_ran"]
  end

  def test_dry_run_reports_up_to_date_system_files
    config = system_files_config(same: "a")

    output = capture_io {
      Dotlayer::Commands::Install.new(config:, detector: stub_detector, dry_run: true).run
    }.first

    assert_match(/System files are up to date/, output)
    refute_match(/hooks/, output)
  end

  private

  # Writes each name's source in the repo; "same" bodies are also written to
  # dest, so they are up to date. Other names have no dest yet, unless the test
  # writes one.
  def package_config
    stub_config(target: @target, repos: [build_repo(path: @repo)], packages: %w[config])
  end

  def system_files_config(**bodies)
    etc = File.join(@repo, "config", "etc")
    FileUtils.mkdir_p(etc)
    entries = bodies.map do |name, body|
      File.write(File.join(etc, "#{name}.conf"), body)
      dest = File.join(@tmpdir, "#{name}.conf")
      File.write(dest, body) if name == :same
      {"source" => "config/etc/#{name}.conf", "dest" => dest}
    end

    stub_config(
      target: @target,
      repos: [build_repo(path: @repo)],
      packages: %w[config],
      system_files: entries,
      hooks: {"after_system_files" => ["echo hook_ran"]}
    )
  end

  def run_install(config, commands_run:, stdin:, **options)
    original_stdin = $stdin
    $stdin = stdin
    capture_io {
      install = Dotlayer::Commands::Install.new(config:, detector: stub_detector, **options)
      install.define_singleton_method(:system) { |*args|
        commands_run << args
        true
      }
      install.run
    }.first
  ensure
    $stdin = original_stdin
  end
end
