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
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [], groups: [])
    detector = Object.new
    detector.define_singleton_method(:detect) { detection }

    output = capture_io {
      Dotlayer::Commands::Install.new(config:, detector:, dry_run: true).run
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
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [], groups: [])
    detector = Object.new
    detector.define_singleton_method(:detect) { detection }

    output = capture_io {
      Dotlayer::Commands::Install.new(config:, detector:).run
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
      system_files: [{ "source" => "foo", "dest" => "/tmp/bar" }]
    )
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [], groups: [])
    detector = Object.new
    detector.define_singleton_method(:detect) { detection }

    output = capture_io {
      Dotlayer::Commands::Install.new(config:, detector:).run
    }.first

    assert_match(/Skipping system files/, output)
  end
end
