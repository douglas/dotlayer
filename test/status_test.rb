require "test_helper"

class StatusTest < Minitest::Test
  include TestConfigHelper

  def test_prints_detection_and_packages
    tmpdir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(tmpdir, "config"))

    config = stub_config(
      repos: [build_repo(path: tmpdir)],
      packages: %w[config]
    )
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: ["omarchy"], groups: ["mycompany"])
    detector = Object.new
    detector.define_singleton_method(:detect) { detection }

    output = capture_io {
      Dotlayer::Commands::Status.new(config:, detector:).run
    }.first

    assert_match(/OS:.*linux/, output)
    assert_match(/Profile:.*desktop/, output)
    assert_match(/Distros:.*omarchy/, output)
    assert_match(/Groups:.*mycompany/, output)
    assert_match(/config/, output)
    assert_match(/1 package/, output)
  ensure
    FileUtils.rm_rf(tmpdir)
  end

  def test_zero_packages_shows_zero_count
    config = stub_config(
      repos: [build_repo(path: "/nonexistent/repo")],
      packages: %w[config]
    )
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [], groups: [])
    detector = Object.new
    detector.define_singleton_method(:detect) { detection }

    output = capture_io {
      Dotlayer::Commands::Status.new(config:, detector:).run
    }.first

    assert_match(/0 package/, output)
  end

  def test_multi_repo_shows_repo_names
    tmpdir1 = Dir.mktmpdir
    tmpdir2 = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(tmpdir1, "config"))
    FileUtils.mkdir_p(File.join(tmpdir2, "fonts"))

    config = stub_config(
      repos: [build_repo(path: tmpdir1), build_repo(path: tmpdir2)],
      packages: %w[config]
    )
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [], groups: [])
    detector = Object.new
    detector.define_singleton_method(:detect) { detection }

    output = capture_io {
      Dotlayer::Commands::Status.new(config:, detector:).run
    }.first

    assert_match(/#{File.basename(tmpdir1)}/, output)
    assert_match(/#{File.basename(tmpdir2)}/, output)
    assert_match(/2 package/, output)
  ensure
    FileUtils.rm_rf(tmpdir1)
    FileUtils.rm_rf(tmpdir2)
  end

  def test_prints_none_when_no_distros_or_groups
    tmpdir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(tmpdir, "config"))

    config = stub_config(
      repos: [build_repo(path: tmpdir)],
      packages: %w[config]
    )
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [], groups: [])
    detector = Object.new
    detector.define_singleton_method(:detect) { detection }

    output = capture_io {
      Dotlayer::Commands::Status.new(config:, detector:).run
    }.first

    assert_match(/Distros:.*\(none\)/, output)
    assert_match(/Groups:.*\(none\)/, output)
  ensure
    FileUtils.rm_rf(tmpdir)
  end
end
