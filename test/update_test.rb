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

    output = capture_io {
      Dotlayer::Commands::Update.new(config:, detector: stub_detector, dry_run: true, self_root: nil).run
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

    output = capture_io {
      Dotlayer::Commands::Update.new(config:, detector: stub_detector, dry_run: true, self_root: nil).run
    }.first

    # Should not mention repo name in pull section (skipped)
    refute_match(/plain/, output)
  end

  def test_live_update_stows_packages
    config = stub_config(
      target: @target,
      repos: [build_repo(path: @repo)],
      packages: %w[config]
    )

    output = capture_io {
      Dotlayer::Commands::Update.new(config:, detector: stub_detector, self_root: nil).run
    }.first

    assert_match(/Restowing.*config/, output)
    assert_match(/1 package/, output)
    assert File.directory?(File.join(@target, ".config"))
    assert File.directory?(File.join(@target, ".config", "test"))
    assert File.symlink?(File.join(@target, ".config", "test", "config.yml")),
      "stow should create file symlinks after update"
  end

  def test_restow_failure_aborts
    File.write(File.join(@target, ".config"), "conflict")
    config = stub_config(
      target: @target,
      repos: [build_repo(path: @repo)],
      packages: %w[config]
    )

    assert_raises(SystemExit) do
      capture_io {
        Dotlayer::Commands::Update.new(config:, detector: stub_detector, self_root: nil).run
      }
    end
  end

  def test_pull_failure_shows_error
    # Create a repo with a remote that will fail to pull
    remote = File.join(@tmpdir, "remote")
    FileUtils.cp_r(@repo, remote)
    # Remove the remote's .git to make pull fail
    local = @repo
    system("git", "-C", local, "remote", "add", "origin", "/nonexistent/remote", out: File::NULL, err: File::NULL)

    config = stub_config(
      target: @target,
      repos: [build_repo(path: local)],
      packages: %w[config]
    )

    output, _ = capture_io {
      Dotlayer::Commands::Update.new(config:, detector: stub_detector, self_root: nil).run
    }

    assert_match(/failed/, output)
  end

  def test_after_runs_only_for_pull_repos_that_changed
    behind = clone_behind("pkgrepo")
    current = clone_behind("biblo", new_commit: false)
    marker = File.join(@tmpdir, "ran")
    config = stub_config(
      target: @target, repos: [], packages: %w[config],
      pull_repos: [
        Dotlayer::PullRepo.new(path: behind, after: "pwd >> #{marker}"),
        Dotlayer::PullRepo.new(path: current, after: "pwd >> #{marker}")
      ]
    )

    result = nil
    output = capture_subprocess_io {
      result = Dotlayer::Commands::Update.new(config:, detector: stub_detector, self_root: nil, env: {}).run
    }.first

    assert result
    assert_equal [File.realpath(behind)], File.readlines(marker, chomp: true)
    assert_match(/pkgrepo\.\.\. .*updated/, output)
    assert_match(/biblo: no new commits/, output)
  end

  def test_failing_after_makes_run_false
    behind = clone_behind("pkgrepo")
    config = stub_config(
      target: @target, repos: [], packages: %w[config],
      pull_repos: [Dotlayer::PullRepo.new(path: behind, after: "exit 3")]
    )

    result = nil
    output = capture_subprocess_io {
      result = Dotlayer::Commands::Update.new(config:, detector: stub_detector, self_root: nil, env: {}).run
    }.first

    refute result
    assert_match(/after-pull failed: exit 3/, output)
  end

  def test_changed_stowed_repo_reexecs_with_the_changed_pull_repos
    dotfiles = clone_behind("dotfiles")
    pkgrepo = clone_behind("pkgrepo")
    config = stub_config(
      target: @target, repos: [build_repo(path: dotfiles)], packages: %w[config],
      pull_repos: [Dotlayer::PullRepo.new(path: pkgrepo, after: "true")]
    )
    reexec_with = nil
    reexec = ->(changed) { reexec_with = changed }

    capture_io {
      Dotlayer::Commands::Update.new(config:, detector: stub_detector, self_root: nil, env: {}, reexec:).run
    }

    assert_equal [pkgrepo], reexec_with
    refute File.exist?(File.join(@target, ".config")), "the re-run restows, not this process"
  end

  def test_rerun_skips_pulls_and_runs_after_for_the_passed_repos
    marker = File.join(@tmpdir, "ran")
    pkgrepo = clone_behind("pkgrepo")
    config = stub_config(
      target: @target, repos: [build_repo(path: @repo)], packages: %w[config],
      pull_repos: [Dotlayer::PullRepo.new(path: pkgrepo, after: "echo ran > #{marker}")]
    )
    env = {Dotlayer::Commands::Update::PULLED_ENV => pkgrepo}

    output = capture_subprocess_io {
      Dotlayer::Commands::Update.new(config:, detector: stub_detector, self_root: nil, env:).run
    }.first

    refute_match(/Pulling repos/, output)
    assert File.exist?(marker)
    refute env.key?(Dotlayer::Commands::Update::PULLED_ENV)
    assert File.symlink?(File.join(@target, ".config", "test", "config.yml"))
  end

  def test_dry_run_lists_after_commands_without_running_them
    pkgrepo = clone_behind("pkgrepo")
    marker = File.join(@tmpdir, "ran")
    config = stub_config(
      target: @target, repos: [], packages: %w[config],
      pull_repos: [Dotlayer::PullRepo.new(path: pkgrepo, after: "touch #{marker}")]
    )

    output = capture_io {
      Dotlayer::Commands::Update.new(config:, detector: stub_detector, dry_run: true, self_root: nil, env: {}).run
    }.first

    assert_match(/would run if the pull brings new commits/, output)
    refute File.exist?(marker)
  end

  def test_reports_unpushed_commits_and_uncommitted_changes
    ahead = clone_behind("pkgrepo", new_commit: false)
    system("git", "-C", ahead, "-c", "user.name=t", "-c", "user.email=t@t",
      "commit", "-q", "--allow-empty", "-m", "local", out: File::NULL, err: File::NULL)
    dirty = clone_behind("biblo", new_commit: false)
    File.write(File.join(dirty, "one"), "edited")
    clean = clone_behind("notes", new_commit: false)
    config = stub_config(
      target: @target, repos: [], packages: %w[config],
      pull_repos: [ahead, dirty, clean].map { |path| Dotlayer::PullRepo.new(path:, after: nil) }
    )

    result = nil
    output = capture_io {
      result = Dotlayer::Commands::Update.new(config:, detector: stub_detector, dry_run: true, self_root: nil, env: {}).run
    }.first

    refute result, "unpushed commits fail the update"
    assert_match(/Not on origin yet/, output)
    assert_match(/pkgrepo: 1 unpushed commit\(s\)/, output)
    assert_match(/biblo: uncommitted changes/, output)
    refute_match(/notes:/, output)
  end

  def test_uncommitted_changes_alone_do_not_fail_the_update
    dirty = clone_behind("biblo", new_commit: false)
    File.write(File.join(dirty, "one"), "edited")
    config = stub_config(
      target: @target, repos: [], packages: %w[config],
      pull_repos: [Dotlayer::PullRepo.new(path: dirty, after: nil)]
    )

    result = nil
    capture_io {
      result = Dotlayer::Commands::Update.new(config:, detector: stub_detector, dry_run: true, self_root: nil, env: {}).run
    }

    assert result
  end

  def test_no_unpushed_report_when_everything_is_on_origin
    clean = clone_behind("notes", new_commit: false)
    config = stub_config(
      target: @target, repos: [], packages: %w[config],
      pull_repos: [Dotlayer::PullRepo.new(path: clean, after: nil)]
    )

    output = capture_io {
      Dotlayer::Commands::Update.new(config:, detector: stub_detector, dry_run: true, self_root: nil, env: {}).run
    }.first

    refute_match(/Not on origin yet/, output)
  end

  private

  # A clone of a new bare remote. With new_commit, the remote then gets a
  # commit the clone doesn't have yet.
  def clone_behind(name, new_commit: true)
    remote = File.join(@tmpdir, "#{name}.git")
    clone = File.join(@tmpdir, name)
    seed = File.join(@tmpdir, "#{name}-seed")
    git = ->(*args) { system("git", *args, out: File::NULL, err: File::NULL) || flunk("git #{args.join(" ")}") }

    git.call("init", "-q", "--bare", "-b", "main", remote)
    git.call("clone", "-q", remote, seed)
    commit = ->(msg) {
      File.write(File.join(seed, msg), msg)
      git.call("-C", seed, "add", ".")
      git.call("-C", seed, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", msg)
      git.call("-C", seed, "push", "-q", "origin", "HEAD:main")
    }
    commit.call("one")
    git.call("clone", "-q", "-b", "main", remote, clone)
    commit.call("two") if new_commit
    clone
  end
end
