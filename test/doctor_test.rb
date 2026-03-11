require "test_helper"

class DoctorTest < Minitest::Test
  include TestConfigHelper

  def test_reports_missing_repo
    config = stub_config(repos: [build_repo(path: "/nonexistent/repo")])

    output = capture_io {
      Dotlayer::Commands::Doctor.new(config:, detector: stub_detector).run
    }.first

    assert_match(/missing/, output)
    assert_match(/1 issue/, output)
  end

  def test_detects_broken_symlinks
    tmpdir = Dir.mktmpdir
    target = File.join(tmpdir, "home")
    repo = File.join(tmpdir, "repo")
    FileUtils.mkdir_p([target, File.join(repo, "config", ".broken_link_target")])

    # Top-level broken symlink in target
    File.symlink("/nonexistent/path", File.join(target, ".broken_link_target"))

    config = stub_config(target: target, repos: [build_repo(path: repo)], packages: %w[config])

    output = capture_io {
      Dotlayer::Commands::Doctor.new(config:, detector: stub_detector).run
    }.first

    assert_match(/Broken symlink/, output)
  ensure
    FileUtils.rm_rf(tmpdir)
  end

  def test_stow_missing_reports_issue
    tmpdir = Dir.mktmpdir
    repo = File.join(tmpdir, "repo")
    FileUtils.mkdir_p(File.join(repo, "config"))

    config = stub_config(target: tmpdir, repos: [build_repo(path: repo)], packages: %w[config])

    original_path = ENV["PATH"]
    ENV["PATH"] = ""
    output = capture_io {
      Dotlayer::Commands::Doctor.new(config:, detector: stub_detector).run
    }.first
    ENV["PATH"] = original_path

    assert_match(/missing/, output)
    assert_match(/Stow is not installed/, output)
  ensure
    ENV["PATH"] = original_path
    FileUtils.rm_rf(tmpdir)
  end

  def test_missing_package_directory_reports_issue
    tmpdir = Dir.mktmpdir
    repo = File.join(tmpdir, "repo")
    FileUtils.mkdir_p(repo)

    config = stub_config(target: tmpdir, repos: [build_repo(path: repo)], packages: %w[config])

    # Stub Resolver to return a package whose directory doesn't exist
    fake_resolver = Object.new
    fake_resolver.define_singleton_method(:resolve) { [[repo, "nonexistent-pkg"]] }

    doctor = Dotlayer::Commands::Doctor.new(config:, detector: stub_detector)
    original_new = Dotlayer::Resolver.method(:new)
    Dotlayer::Resolver.define_singleton_method(:new) { |**_| fake_resolver }

    output = capture_io { doctor.run }.first

    assert_match(/Package directory missing/, output)
  ensure
    Dotlayer::Resolver.define_singleton_method(:new, original_new) if original_new
    FileUtils.rm_rf(tmpdir)
  end

  def test_multiple_issues_reports_count
    config = stub_config(
      repos: [build_repo(path: "/nonexistent/repo1"), build_repo(path: "/nonexistent/repo2")]
    )

    output = capture_io {
      Dotlayer::Commands::Doctor.new(config:, detector: stub_detector).run
    }.first

    assert_match(/2 issue/, output)
  end

  def test_no_issues_when_healthy
    tmpdir = Dir.mktmpdir
    repo = File.join(tmpdir, "repo")
    FileUtils.mkdir_p(File.join(repo, "config"))

    config = stub_config(target: tmpdir, repos: [build_repo(path: repo)], packages: %w[config])

    output = capture_io {
      Dotlayer::Commands::Doctor.new(config:, detector: stub_detector).run
    }.first

    assert_match(/No issues found/, output)
  ensure
    FileUtils.rm_rf(tmpdir)
  end
end
