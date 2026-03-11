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
    # Stow should have created symlinks
    config_test = File.join(@target, ".config", "test")
    config_dir = File.join(@target, ".config")
    assert File.symlink?(config_dir) || File.symlink?(config_test),
      "stow should create symlinks in target"
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
      system_files: [{"source" => "config/etc/test.conf", "dest" => "/tmp/test.conf"}],
      hooks: {}
    )

    output = capture_io {
      Dotlayer::Commands::Install.new(config:, detector: stub_detector, dry_run: true).run
    }.first

    assert_match(/System files/, output)
    assert_match(/dry-run/, output)
    refute File.exist?("/tmp/test.conf")
  end

  def test_system_files_stdin_reject_skips
    config = stub_config(
      target: @target,
      repos: [build_repo(path: @repo)],
      packages: %w[config],
      system_files: [{"source" => "config/etc/test.conf", "dest" => "/tmp/test.conf"}],
      hooks: {}
    )

    original_stdin = $stdin
    $stdin = StringIO.new("n\n")
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
      system_files: [{"source" => "config/etc/test.conf", "dest" => "/tmp/dotlayer_hook_test"}],
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
      system_files: [{"source" => "config/etc/test.conf", "dest" => "/tmp/dotlayer_hook_test"}],
      hooks: {"after_system_files" => ["echo hook_ran"]}
    )

    # First "y" accepts system files install, second "n" rejects hooks
    original_stdin = $stdin
    $stdin = StringIO.new("y\nn\n")
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
      system_files: [{"source" => "config/etc/test.conf", "dest" => "/tmp/dotlayer_hook_test"}],
      hooks: {"after_system_files" => ["echo hook_ran"]}
    )

    # "y" accepts system files, "y" accepts hooks
    original_stdin = $stdin
    $stdin = StringIO.new("y\ny\n")
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
end
