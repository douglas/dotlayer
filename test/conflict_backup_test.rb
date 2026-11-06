require "test_helper"

class ConflictBackupTest < Minitest::Test
  include TestConfigHelper

  NOW = Time.new(2026, 1, 2, 3, 4, 5)

  def setup
    @tmpdir = Dir.mktmpdir
    @target = File.join(@tmpdir, "home")
    @repo = File.join(@tmpdir, "repo")
    @pkg = File.join(@repo, "config")
    @backup = File.join(@target, "dotfiles-conflicts-20260102-030405")
    FileUtils.mkdir_p([File.join(@target, ".config", "app"), File.join(@pkg, ".config", "app")])
    @original_home = ENV["HOME"]
    # Stow reads its global ignore list from $HOME; use the built-in one.
    ENV["HOME"] = @tmpdir
  end

  def teardown
    ENV["HOME"] = @original_home
    FileUtils.rm_rf(@tmpdir)
  end

  def test_removes_identical_files_and_moves_different_ones
    repo_file(".config/app/same.conf", "a")
    repo_file(".config/app/diff.conf", "repo")
    live_file(".config/app/same.conf", "a")
    live_file(".config/app/diff.conf", "mine")

    output = capture_io { @count = backup.resolve(@repo, "config") }.first

    assert_equal 2, @count
    refute File.exist?(File.join(@target, ".config", "app", "same.conf"))
    refute File.exist?(File.join(@target, ".config", "app", "diff.conf"))
    assert_equal "mine", File.read(File.join(@backup, ".config", "app", "diff.conf"))
    refute File.exist?(File.join(@backup, ".config", "app", "same.conf"))
    assert_match(/removing identical file: \.config\/app\/same\.conf/, output)
    assert_match(/moving to backup: \.config\/app\/diff\.conf/, output)
    assert Dotlayer::Stow.new(target: @target, quiet: true).restow(@repo, "config")
  end

  def test_moves_links_that_point_outside_the_repos
    repo_file(".config/app/theme.conf", "repo")
    FileUtils.mkdir_p(File.join(@tmpdir, "elsewhere"))
    File.write(File.join(@tmpdir, "elsewhere", "theme.conf"), "theme")
    File.symlink(File.join(@tmpdir, "elsewhere", "theme.conf"), File.join(@target, ".config", "app", "theme.conf"))

    capture_io { backup.resolve(@repo, "config") }

    assert File.symlink?(File.join(@backup, ".config", "app", "theme.conf"))
    refute File.symlink?(File.join(@target, ".config", "app", "theme.conf"))
  end

  def test_leaves_links_into_a_repo_alone
    repo_file(".config/app/own.conf", "repo")
    File.symlink(File.join(@pkg, ".config", "app", "own.conf"), File.join(@target, ".config", "app", "own.conf"))

    assert_equal 0, backup.resolve(@repo, "config")
    refute File.exist?(@backup)
  end

  def test_leaves_files_reached_through_a_folded_parent_alone
    repo_file(".config/app/own.conf", "repo")
    FileUtils.rm_rf(File.join(@target, ".config", "app"))
    File.symlink(File.join(@pkg, ".config", "app"), File.join(@target, ".config", "app"))

    assert_equal 0, backup.resolve(@repo, "config")
    assert File.symlink?(File.join(@target, ".config", "app"))
  end

  def test_leaves_files_stow_ignores
    repo_file(".config/app/.gitignore", "repo")
    live_file(".config/app/.gitignore", "mine")

    assert_equal 0, backup.resolve(@repo, "config")
    assert_equal "mine", File.read(File.join(@target, ".config", "app", ".gitignore"))
  end

  def test_leaves_real_directories_alone
    repo_file(".config/app/sub", "repo")
    FileUtils.mkdir_p(File.join(@target, ".config", "app", "sub"))

    assert_equal 0, backup.resolve(@repo, "config")
    assert File.directory?(File.join(@target, ".config", "app", "sub"))
  end

  def test_dry_run_changes_nothing
    repo_file(".config/app/diff.conf", "repo")
    live_file(".config/app/diff.conf", "mine")
    resolver = backup(dry_run: true)

    output = capture_io {
      assert_equal 1, resolver.resolve(@repo, "config")
      resolver.summary
    }.first

    assert_equal "mine", File.read(File.join(@target, ".config", "app", "diff.conf"))
    refute File.exist?(@backup)
    assert_match(/would move to backup/, output)
    assert_match(/would be moved/, output)
  end

  def test_summary_names_the_backup_dir_only_when_something_moved
    repo_file(".config/app/same.conf", "a")
    live_file(".config/app/same.conf", "a")
    resolver = backup

    output = capture_io {
      resolver.resolve(@repo, "config")
      resolver.summary
    }.first

    assert_match(/1 identical file\(s\) removed, 0 different file\(s\) moved/, output)
    refute_match(/dotfiles-conflicts/, output)
    refute File.exist?(@backup)
  end

  private

  def backup(dry_run: false)
    config = stub_config(target: @target, repos: [build_repo(path: @repo)], packages: %w[config])
    Dotlayer::ConflictBackup.new(config:, dry_run:, now: NOW)
  end

  def repo_file(rel, body)
    FileUtils.mkdir_p(File.dirname(File.join(@pkg, rel)))
    File.write(File.join(@pkg, rel), body)
  end

  def live_file(rel, body)
    FileUtils.mkdir_p(File.dirname(File.join(@target, rel)))
    File.write(File.join(@target, rel), body)
  end
end
