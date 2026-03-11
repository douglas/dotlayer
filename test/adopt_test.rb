require "test_helper"

class AdoptTest < Minitest::Test
  include TestConfigHelper

  def setup
    @tmpdir = Dir.mktmpdir
    @target = File.join(@tmpdir, "home")
    @repo = File.join(@tmpdir, "repo")
    FileUtils.mkdir_p([@target, File.join(@repo, "config")])
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_dry_run_does_not_move_files
    source = File.join(@target, ".config", "lazygit")
    FileUtils.mkdir_p(source)
    File.write(File.join(source, "config.yml"), "theme: dark")

    run_adopt(paths: [source], dry_run: true)

    assert File.exist?(source), "dry-run should not move files"
    refute File.symlink?(source), "source should still be a real directory"
    dest = File.join(@repo, "config", ".config", "lazygit")
    refute File.exist?(dest), "dry-run should not create dest"
  end

  def test_moves_directory_into_package
    source = File.join(@target, ".config", "lazygit")
    FileUtils.mkdir_p(source)
    File.write(File.join(source, "config.yml"), "theme: dark")

    run_adopt(paths: [source])

    dest = File.join(@repo, "config", ".config", "lazygit", "config.yml")
    assert File.exist?(dest), "config.yml should be moved into package"
    assert_equal "theme: dark", File.read(dest)
    # After restow, original path becomes a symlink managed by stow
    if File.symlink?(source)
      refute File.realpath(source).start_with?(@target), "source should point into repo after restow"
    else
      # stow not available — file was moved but no symlink was created back
      refute File.exist?(source), "source should have been moved"
    end
  end

  def test_moves_single_file
    FileUtils.mkdir_p(File.join(@target, ".config"))
    source = File.join(@target, ".config", "starship.toml")
    File.write(source, "format = '$all'")

    run_adopt(paths: [source])

    dest = File.join(@repo, "config", ".config", "starship.toml")
    assert File.exist?(dest)
    assert_equal "format = '$all'", File.read(dest)
  end

  def test_adopts_multiple_paths
    lazygit = File.join(@target, ".config", "lazygit")
    lazydocker = File.join(@target, ".config", "lazydocker")
    FileUtils.mkdir_p([lazygit, lazydocker])
    File.write(File.join(lazygit, "config.yml"), "git")
    File.write(File.join(lazydocker, "config.yml"), "docker")

    run_adopt(paths: [lazygit, lazydocker])

    assert File.exist?(File.join(@repo, "config", ".config", "lazygit", "config.yml"))
    assert File.exist?(File.join(@repo, "config", ".config", "lazydocker", "config.yml"))
  end

  def test_skips_already_existing_in_package
    source = File.join(@target, ".config", "lazygit")
    FileUtils.mkdir_p(source)

    dest = File.join(@repo, "config", ".config", "lazygit")
    FileUtils.mkdir_p(dest)

    run_adopt(paths: [source])

    # Source should remain untouched (not moved)
    assert File.directory?(source)
    refute File.symlink?(source)
  end

  def test_rejects_path_outside_target
    outside = File.join(@tmpdir, "outside", "stuff")
    FileUtils.mkdir_p(outside)

    assert_raises(SystemExit) do
      run_adopt(paths: [outside])
    end
  end

  def test_skips_nonexistent_source
    missing = File.join(@target, ".config", "nope")

    # Should not raise, just warn and continue
    run_adopt(paths: [missing])
  end

  def test_private_flag_uses_private_repo
    private_repo = File.join(@tmpdir, "private_dotfiles")
    FileUtils.mkdir_p(private_repo)

    source = File.join(@target, ".config", "lazysql")
    FileUtils.mkdir_p(source)
    File.write(File.join(source, "config.toml"), "db_url = secret")

    config = stub_config(
      target: @target,
      repos: [build_repo(path: @repo), build_repo(path: private_repo, private: true)]
    )
    Dotlayer::Commands::Adopt.new(
      config:, paths: [source], package: "config", private_repo: true
    ).run

    dest = File.join(private_repo, "config", ".config", "lazysql", "config.toml")
    assert File.exist?(dest), "should move into private repo"
    assert_equal "db_url = secret", File.read(dest)
  rescue Errno::ENOENT
    # stow binary not found — file moves already happened
  end

  private

  def run_adopt(paths:, dry_run: false)
    config = stub_config(target: @target, repos: [build_repo(path: @repo)])
    Dotlayer::Commands::Adopt.new(
      config:, paths:, package: "config", dry_run:
    ).run
  rescue Errno::ENOENT
    # stow binary not found on some CI — file moves already happened
  end
end
