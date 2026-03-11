require "test_helper"

class UpdateTest < Minitest::Test
  include TestConfigHelper

  def setup
    @tmpdir = Dir.mktmpdir
    @target = File.join(@tmpdir, "home")
    @repo = File.join(@tmpdir, "repo")
    FileUtils.mkdir_p([@target, File.join(@repo, "config", ".config", "test")])
    File.write(File.join(@repo, "config", ".config", "test", "config.yml"), "hello")

    # Init a git repo so pull_repos has something to work with
    system("git", "-C", @repo, "init", "-q", out: File::NULL, err: File::NULL)
    system("git", "-C", @repo, "add", ".", out: File::NULL, err: File::NULL)
    system("git", "-C", @repo, "commit", "-m", "init", "-q", out: File::NULL, err: File::NULL)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_dry_run_does_not_pull_or_stow
    config = stub_config(
      target: @target,
      repos: [build_repo(path: @repo)],
      packages: %w[config]
    )
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [], groups: [])
    detector = Object.new
    detector.define_singleton_method(:detect) { detection }

    output = capture_io {
      Dotlayer::Commands::Update.new(config:, detector:, dry_run: true).run
    }.first

    assert_match(/dry-run/, output)
    assert_match(/1 package/, output)
    refute File.exist?(File.join(@target, ".config", "test"))
  end

  def test_skips_repos_without_git
    non_git_repo = File.join(@tmpdir, "plain")
    FileUtils.mkdir_p(File.join(non_git_repo, "config"))

    config = stub_config(
      target: @target,
      repos: [build_repo(path: non_git_repo)],
      packages: %w[config]
    )
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [], groups: [])
    detector = Object.new
    detector.define_singleton_method(:detect) { detection }

    output = capture_io {
      Dotlayer::Commands::Update.new(config:, detector:, dry_run: true).run
    }.first

    # Should not mention repo name in pull section (skipped)
    refute_match(/plain/, output)
  end
end
