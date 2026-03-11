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

  def test_stow_missing_reports_issue
    tmpdir = Dir.mktmpdir
    repo = File.join(tmpdir, "repo")
    FileUtils.mkdir_p(File.join(repo, "config"))

    config = stub_config(target: tmpdir, repos: [build_repo(path: repo)], packages: %w[config])
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [], groups: [])
    detector = Object.new
    detector.define_singleton_method(:detect) { detection }

    original_path = ENV["PATH"]
    ENV["PATH"] = ""
    output = capture_io {
      Dotlayer::Commands::Doctor.new(config:, detector:).run
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
    # Stub resolver to return a package whose directory does not exist
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [], groups: [])
    detector = Object.new
    detector.define_singleton_method(:detect) { detection }

    doctor = Dotlayer::Commands::Doctor.new(config:, detector:)
    # Override resolve to return a fake package
    original_run = doctor.method(:run)
    doctor.define_singleton_method(:run) do
      detection = detector.detect
      @packages = [[repo, "nonexistent-pkg"]]
      # Call private methods via send
      instance_variable_set(:@issues, [])
      heading "Dotlayer Doctor"
      puts
      send(:check_stow_installed)
      send(:check_repos_exist)
      send(:check_packages_exist, @packages)
      send(:check_broken_symlinks)
      puts
      if instance_variable_get(:@issues).empty?
        ok "No issues found."
      else
        issues = instance_variable_get(:@issues)
        error "#{issues.size} issue(s) found:"
        issues.each { |issue| puts "  - #{issue}" }
      end
    end

    output = capture_io { doctor.run }.first

    assert_match(/Package directory missing/, output)
  ensure
    FileUtils.rm_rf(tmpdir)
  end

  def test_top_level_broken_symlink_detected
    tmpdir = Dir.mktmpdir
    target = File.join(tmpdir, "home")
    repo = File.join(tmpdir, "repo")
    FileUtils.mkdir_p([target, File.join(repo, "config", ".broken_link_target")])

    # Create a top-level broken symlink directly in target
    File.symlink("/nonexistent/path", File.join(target, ".broken_link_target"))

    config = stub_config(target: target, repos: [build_repo(path: repo)], packages: %w[config])
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

  def test_multiple_issues_reports_count
    config = stub_config(
      repos: [build_repo(path: "/nonexistent/repo1"), build_repo(path: "/nonexistent/repo2")]
    )
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [], groups: [])
    detector = Object.new
    detector.define_singleton_method(:detect) { detection }

    output = capture_io {
      Dotlayer::Commands::Doctor.new(config:, detector:).run
    }.first

    assert_match(/2 issue/, output)
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
