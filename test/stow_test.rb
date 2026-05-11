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

    assert_predicate stow, :dry_run?
    assert stow.restow(@repo, "pkg")
    refute File.exist?(File.join(@target, ".config", "test"))
  end

  def test_restow_creates_symlinks
    stow = Dotlayer::Stow.new(target: @target)

    assert stow.restow(@repo, "pkg")
    assert File.directory?(File.join(@target, ".config"))
    assert File.directory?(File.join(@target, ".config", "test"))
    assert File.symlink?(File.join(@target, ".config", "test", "config.yml")),
      "stow should create file symlinks without folding parent directories"
  end

  def test_restow_allows_later_packages_to_share_parent_directories
    first_repo = File.join(@tmpdir, "first")
    second_repo = File.join(@tmpdir, "second")
    FileUtils.mkdir_p(File.join(first_repo, "pkg", ".local", "share", "first"))
    FileUtils.mkdir_p(File.join(second_repo, "pkg", ".local", "share", "second"))
    File.write(File.join(first_repo, "pkg", ".local", "share", "first", "config"), "first")
    File.write(File.join(second_repo, "pkg", ".local", "share", "second", "config"), "second")

    stow = Dotlayer::Stow.new(target: @target)

    assert stow.restow(first_repo, "pkg")
    assert stow.restow(second_repo, "pkg")
    assert File.symlink?(File.join(@target, ".local", "share", "first", "config"))
    assert File.symlink?(File.join(@target, ".local", "share", "second", "config"))
  end

  def test_restow_failure_sets_last_error
    stow = Dotlayer::Stow.new(target: @target)

    # Nonexistent package should fail
    refute stow.restow(@repo, "nonexistent")
    assert stow.last_error
    refute_empty stow.last_error
  end

  def test_last_error_cleared_after_success
    stow = Dotlayer::Stow.new(target: @target)

    # First, cause a failure
    stow.restow(@repo, "nonexistent")
    assert stow.last_error

    # Then succeed — last_error should be cleared
    stow.restow(@repo, "pkg")
    assert_nil stow.last_error
  end

  def test_verbose_prints_command_to_stderr
    stow = Dotlayer::Stow.new(target: @target, verbose: true)

    _, err = capture_io { stow.restow(@repo, "pkg") }

    assert_match(/stow -R --no-folding -v/, err)
  end

  def test_dry_run_prints_command_to_stderr
    stow = Dotlayer::Stow.new(target: @target, dry_run: true)

    _, err = capture_io { stow.restow(@repo, "pkg") }

    assert_match(/stow -R --no-folding/, err)
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
