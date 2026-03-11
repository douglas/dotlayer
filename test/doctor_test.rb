require "test_helper"

class DoctorTest < Minitest::Test
  include TestConfigHelper

  def test_reports_missing_repo
    config = stub_config(repos: [build_repo(path: "/nonexistent/repo")])
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [], groups: [])
    detector = Object.new
    detector.define_singleton_method(:detect) { detection }

    output = capture_io {
      Dotlayer::Commands::Doctor.new(config:, detector:).run
    }.first

    assert_match(/missing/, output)
    assert_match(/1 issue/, output)
  end

  def test_detects_broken_symlinks
    tmpdir = Dir.mktmpdir
    target = File.join(tmpdir, "home")
    repo = File.join(tmpdir, "repo")
    FileUtils.mkdir_p([target, File.join(repo, "config", ".config", "test")])
    File.write(File.join(repo, "config", ".config", "test", "real.txt"), "content")

    # Create a broken symlink in target
    config_dir = File.join(target, ".config", "test")
    FileUtils.mkdir_p(config_dir)
    File.symlink("/nonexistent/path", File.join(config_dir, "broken.txt"))

    config = stub_config(target: target, repos: [build_repo(path: repo)])
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [], groups: [])
    detector = Object.new
    detector.define_singleton_method(:detect) { detection }

    output = capture_io {
      Dotlayer::Commands::Doctor.new(config:, detector:).run
    }.first

    assert_match(/Broken symlink/, output)
  ensure
    FileUtils.rm_rf(tmpdir)
  end

  def test_no_issues_when_healthy
    tmpdir = Dir.mktmpdir
    repo = File.join(tmpdir, "repo")
    FileUtils.mkdir_p(File.join(repo, "config"))

    config = stub_config(target: tmpdir, repos: [build_repo(path: repo)], packages: %w[config])
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [], groups: [])
    detector = Object.new
    detector.define_singleton_method(:detect) { detection }

    output = capture_io {
      Dotlayer::Commands::Doctor.new(config:, detector:).run
    }.first

    assert_match(/No issues found/, output)
  ensure
    FileUtils.rm_rf(tmpdir)
  end
end
