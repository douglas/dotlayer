require "test_helper"

class DetectorTest < Minitest::Test
  def test_detect_os_linux
    detector = Dotlayer::Detector.new(config: Dotlayer::Config.new)
    detection = detector.detect

    # We're running on Linux
    assert_equal "linux", detection.os
  end

  def test_detect_profile_from_env
    config = Dotlayer::Config.new
    ENV["DOTLAYER_PROFILE"] = "laptop"

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    assert_equal "laptop", detection.profile
  ensure
    ENV.delete("DOTLAYER_PROFILE")
  end

  def test_detect_profile_falls_back_to_desktop
    config = Dotlayer::Config.new
    # Stub profile_detect to a command that fails
    config.define_singleton_method(:profile_detect) { "false" }
    config.define_singleton_method(:profile_env) { "DOTLAYER_TEST_NONEXISTENT" }

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    assert_equal "desktop", detection.profile
  end

  def test_detection_is_immutable
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: ["omarchy"], groups: ["mycompany"])

    assert_equal "linux", detection.os
    assert_equal "desktop", detection.profile
    assert_equal ["omarchy"], detection.distros
    assert_equal ["mycompany"], detection.groups
    assert_raises(NoMethodError) { detection.os = "macos" }
  end

  def test_detect_distro_with_command
    config = Dotlayer::Config.new
    config.define_singleton_method(:distros) {
      { "test_distro" => { "detect" => "true" } }
    }

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    assert_includes detection.distros, "test_distro"
  end

  def test_detect_distro_not_found
    config = Dotlayer::Config.new
    config.define_singleton_method(:distros) {
      { "missing_distro" => { "detect" => "false" } }
    }

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    refute_includes detection.distros, "missing_distro"
  end

  def test_detect_group_with_command
    config = Dotlayer::Config.new
    config.define_singleton_method(:groups) {
      { "mycompany" => { "detect" => "true" } }
    }

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    assert_includes detection.groups, "mycompany"
  end

  def test_detect_group_not_found
    config = Dotlayer::Config.new
    config.define_singleton_method(:groups) {
      { "acme" => { "detect" => "false" } }
    }

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    refute_includes detection.groups, "acme"
  end
end
