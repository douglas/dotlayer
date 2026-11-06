require "test_helper"
require "open3"

class HooksTest < Minitest::Test
  include TestConfigHelper

  GIT_ENV = {
    "GIT_AUTHOR_NAME" => "t", "GIT_AUTHOR_EMAIL" => "t@t", "GIT_COMMITTER_NAME" => "t",
    "GIT_COMMITTER_EMAIL" => "t@t", "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_SYSTEM" => "/dev/null"
  }.freeze

  def setup
    @tmpdir = Dir.mktmpdir
    @repo = File.join(@tmpdir, "dots")
    @other = File.join(@tmpdir, "other")
    [@repo, @other].each { |path| git(@tmpdir, "init", "-q", path) }
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_install_writes_both_hooks_and_is_idempotent
    output, ok = run_hooks("install")

    assert ok
    assert_match(/post-merge: installing/, output)
    Dotlayer::Commands::Hooks::NAMES.each do |name|
      path = File.join(@repo, ".git", "hooks", name)
      assert File.executable?(path), name
      assert_includes File.read(path), Dotlayer::Commands::Hooks::MARKER
      assert_match(/dotlayer install --quiet <\/dev\/null/, File.read(path))
    end
    before = File.read(hook("post-merge"))

    output, ok = run_hooks("install")

    assert ok
    assert_match(/post-merge: already installed/, output)
    assert_equal before, File.read(hook("post-merge"))
  end

  def test_install_refuses_to_touch_a_foreign_hook
    FileUtils.mkdir_p(File.dirname(hook("post-merge")))
    File.write(hook("post-merge"), "#!/bin/sh\necho mine\n")

    output, ok = run_hooks("install")

    refute ok
    assert_match(/refusing to touch it/, output)
    assert_equal "#!/bin/sh\necho mine\n", File.read(hook("post-merge"))
    assert File.exist?(hook("post-rewrite")), "the other hook is still written"
  end

  def test_core_hooks_path_is_respected_and_nothing_is_written
    git(@repo, "config", "core.hooksPath", "/somewhere/hooks")

    output, ok = run_hooks("install")

    assert ok
    assert_match(%r{core\.hooksPath is set \(/somewhere/hooks\)}, output)
    refute File.exist?(hook("post-merge"))
  end

  def test_uninstall_removes_only_our_hooks
    run_hooks("install")
    File.write(hook("post-rewrite"), "#!/bin/sh\necho mine\n")

    output, ok = run_hooks("uninstall")

    assert ok
    refute File.exist?(hook("post-merge"))
    assert_equal "#!/bin/sh\necho mine\n", File.read(hook("post-rewrite"))
    assert_match(/post-rewrite: not written by dotlayer/, output)
  end

  def test_dry_run_writes_nothing
    output, = run_hooks("install", dry_run: true)

    assert_match(/post-merge: installing/, output)
    refute File.exist?(hook("post-merge"))
  end

  def test_missing_and_non_git_repos_are_skipped
    plain = File.join(@tmpdir, "plain")
    FileUtils.mkdir_p(plain)
    config = stub_config(repos: [build_repo(path: plain), build_repo(path: File.join(@tmpdir, "gone"))])

    output = capture_io { assert Dotlayer::Commands::Hooks.new(config:, action: "install").run }.first

    assert_match(/not a git repo, skipped/, output)
    assert_match(/missing, skipped/, output)
  end

  def test_config_path_is_baked_in_only_when_given_with_c
    {"-c" => true, "discovered" => false}.each do |source, baked|
      FileUtils.rm_f(hook("post-merge"))
      config = stub_config(repos: [build_repo(path: @repo)], path: "/x/my config.yml", source:)

      capture_io { Dotlayer::Commands::Hooks.new(config:, action: "install").run }

      script = File.read(hook("post-merge"))
      assert_equal baked, script.include?("exec dotlayer -c /x/my\\ config.yml install --quiet </dev/null"), source
      assert_includes script, "install --quiet </dev/null"
    end
  end

  def test_git_pull_runs_the_hook_and_post_rewrite_only_for_rebase
    log = File.join(@tmpdir, "calls.log")
    bin = File.join(@tmpdir, "bin")
    FileUtils.mkdir_p(bin)
    File.write(File.join(bin, "dotlayer"), "#!/bin/sh\necho \"$@\" >> #{log}\n[ -t 0 ] && echo tty >> #{log}\nexit 0\n")
    File.chmod(0o755, File.join(bin, "dotlayer"))
    run_hooks("install")

    # An upstream with one commit, cloned as the repo with hooks.
    origin = File.join(@tmpdir, "origin.git")
    git(@tmpdir, "init", "-q", "--bare", origin)
    git(@other, "checkout", "-q", "-b", "main")
    File.write(File.join(@other, "a"), "1")
    git(@other, "add", "a")
    git(@other, "commit", "-q", "-m", "one")
    git(@other, "remote", "add", "origin", origin)
    git(@other, "push", "-q", "origin", "main")
    git(@repo, "remote", "add", "origin", origin)
    git(@repo, "fetch", "-q", "origin")
    git(@repo, "checkout", "-q", "-b", "main", "origin/main")

    File.write(File.join(@other, "a"), "2")
    git(@other, "commit", "-q", "-am", "two")
    git(@other, "push", "-q", "origin", "main")
    File.delete(log) if File.exist?(log)
    git(@repo, "pull", "-q", "--no-rebase", env: {"PATH" => "#{bin}:#{ENV["PATH"]}"})

    assert_equal "install --quiet\n", File.read(log)

    File.delete(log)
    run_script("post-rewrite", "amend", bin)
    refute File.exist?(log)
    run_script("post-rewrite", "rebase", bin)
    assert_equal "install --quiet\n", File.read(log)
  end

  private

  def hook(name)
    File.join(@repo, ".git", "hooks", name)
  end

  def run_hooks(action, dry_run: false)
    config = stub_config(repos: [build_repo(path: @repo)], source: "discovered")
    ok = nil
    output = capture_io { ok = Dotlayer::Commands::Hooks.new(config:, action:, dry_run:).run }.first
    [output.gsub(/\e\[[0-9;]*m/, ""), ok]
  end

  def run_script(name, arg, bin)
    Open3.capture2e({"PATH" => "#{bin}:#{ENV["PATH"]}"}, "sh", hook(name), arg, stdin_data: "")
  end

  def git(dir, *args, env: {})
    output, status = Open3.capture2e(GIT_ENV.merge(env), "git", "-C", dir, *args)
    assert status.success?, "git #{args.join(" ")}: #{output}"
    output
  end
end
