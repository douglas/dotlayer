require "test_helper"

class StowTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @target = File.join(@tmpdir, "home")
    @repo = File.join(@tmpdir, "repo")
    FileUtils.mkdir_p([@target, File.join(@repo, "pkg", ".config", "test")])
    File.write(File.join(@repo, "pkg", ".config", "test", "config.yml"), "hello")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_dry_run_does_not_create_symlinks
    stow = Dotlayer::Stow.new(target: @target, dry_run: true)

    assert stow.dry_run?
    assert stow.restow(@repo, "pkg")
    refute File.exist?(File.join(@target, ".config", "test"))
  end

  def test_restow_creates_symlinks
    stow = Dotlayer::Stow.new(target: @target)

    assert stow.restow(@repo, "pkg")
    # Stow tree-folds: may symlink .config directly or .config/test
    config_dir = File.join(@target, ".config")
    assert File.symlink?(config_dir) || File.symlink?(File.join(config_dir, "test")),
      "stow should create symlinks in target"
  end

  def test_restow_failure_sets_last_error
    stow = Dotlayer::Stow.new(target: @target)

    # Nonexistent package should fail
    refute stow.restow(@repo, "nonexistent")
    assert stow.last_error
    refute_empty stow.last_error
  end

  def test_missing_stow_binary_sets_error
    stow = Dotlayer::Stow.new(target: @target)

    original_path = ENV["PATH"]
    ENV["PATH"] = ""
    refute stow.restow(@repo, "pkg")
    assert_match(/not installed/i, stow.last_error)
  ensure
    ENV["PATH"] = original_path
  end
end
