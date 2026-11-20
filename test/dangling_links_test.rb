require "test_helper"

class DanglingLinksTest < Minitest::Test
  include TestConfigHelper

  def setup
    @tmpdir = Dir.mktmpdir
    @target = File.join(@tmpdir, "home")
    @repo = File.join(@tmpdir, "repo")
    @gone = File.join(@repo, "config", ".config", "xremap", "config.yml")
    FileUtils.mkdir_p([File.join(@repo, "config", ".config"), File.join(@target, ".config")])
    @config = stub_config(target: @target, repos: [build_repo(path: @repo)], packages: %w[config])
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_removes_dangling_link_into_repo
    link = link_into_repo(".config/xremap/config.yml")

    output = prune

    refute File.symlink?(link)
    assert_match(%r{removed #{link}}, output)
  end

  def test_keeps_link_whose_target_exists
    FileUtils.mkdir_p(File.dirname(@gone))
    File.write(@gone, "x")
    link = link_into_repo(".config/xremap/config.yml")

    prune

    assert File.symlink?(link)
  end

  def test_keeps_dangling_link_outside_the_repos
    link = File.join(@target, ".config", "outside")
    File.symlink(File.join(@tmpdir, "elsewhere", "gone"), link)

    prune

    assert File.symlink?(link)
  end

  def test_keeps_regular_file
    file = File.join(@target, ".config", "plain")
    File.write(file, "mine")

    prune

    assert_equal "mine", File.read(file)
  end

  def test_removes_empty_parents_but_not_top_level_dirs
    link = link_into_repo(".config/systemd/user/wants/xremap.service")

    output = prune

    refute File.exist?(File.join(@target, ".config", "systemd"))
    assert File.directory?(File.join(@target, ".config"))
    assert File.directory?(@target)
    assert_match(%r{removed empty directory #{File.dirname(link)}}, output)
  end

  def test_keeps_parents_that_still_hold_something
    link_into_repo(".config/app/stale")
    File.write(File.join(@target, ".config", "app", "settings"), "mine")

    prune

    assert File.exist?(File.join(@target, ".config", "app", "settings"))
  end

  def test_keeps_top_level_dir_when_it_becomes_empty
    link_into_repo(".config/stale")

    prune

    assert File.directory?(File.join(@target, ".config"))
  end

  def test_dry_run_removes_nothing
    link = link_into_repo(".config/xremap/config.yml")

    output = prune(dry_run: true)

    assert File.symlink?(link)
    assert_match(%r{would remove #{link}}, output)
  end

  private

  def link_into_repo(relative)
    link = File.join(@target, relative)
    FileUtils.mkdir_p(File.dirname(link))
    File.symlink(File.join(@repo, "config", relative), link)
    link
  end

  def prune(**options)
    capture_io {
      Dotlayer::DanglingLinks.new(config: @config, packages: [[@repo, "config"]]).prune(**options)
    }.first
  end
end
