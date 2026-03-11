require "test_helper"

class DetectorTest < Minitest::Test
  include TestConfigHelper

  def test_detect_os_linux
    detector = Dotlayer::Detector.new(config: Dotlayer::Config.new)
    detection = detector.detect

    assert_equal "linux", detection.os
  end

  def test_detect_profile_from_env
    ENV["DOTLAYER_PROFILE"] = "laptop"

    detector = Dotlayer::Detector.new(config: Dotlayer::Config.new)
    detection = detector.detect

    assert_equal "laptop", detection.profile
  ensure
    ENV.delete("DOTLAYER_PROFILE")
  end

  def test_detect_profile_falls_back_to_desktop
    config = stub_config(profile_detect: "false", profile_env: "DOTLAYER_TEST_NONEXISTENT")

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    assert_equal "desktop", detection.profile
  end

  def test_detect_distro_with_command
    config = stub_config(distros: {"test_distro" => {"detect" => "true"}})

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    assert_includes detection.distros, "test_distro"
  end

  def test_detect_distro_not_found
    config = stub_config(distros: {"missing_distro" => {"detect" => "false"}})

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    refute_includes detection.distros, "missing_distro"
  end

  def test_detect_group_with_command
    config = stub_config(groups: {"mycompany" => {"detect" => "true"}})

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    assert_includes detection.groups, "mycompany"
  end

  def test_detect_group_not_found
    config = stub_config(groups: {"acme" => {"detect" => "false"}})

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    refute_includes detection.groups, "acme"
  end

  def test_detect_profile_from_command
    config = stub_config(
      profile_detect: "echo laptop",
      profile_env: "DOTLAYER_TEST_NONEXISTENT"
    )

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    assert_equal "laptop", detection.profile
  end

  def test_invalid_detect_values_skipped
    [{"detect" => ""}, {}, {"detect" => 42}].each do |entry|
      config = stub_config(distros: {"broken" => entry})

      detector = Dotlayer::Detector.new(config: config)
      detection = detector.detect

      refute_includes detection.distros, "broken"
    end
  end

  def test_empty_profile_detect_falls_back_to_desktop
    config = stub_config(profile_detect: "", profile_env: "DOTLAYER_TEST_NONEXISTENT")

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    assert_equal "desktop", detection.profile
  end

  def test_empty_env_var_falls_through_to_command
    ENV["DOTLAYER_PROFILE"] = ""
    config = stub_config(profile_detect: "echo laptop", profile_env: "DOTLAYER_PROFILE")

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    assert_equal "laptop", detection.profile
  ensure
    ENV.delete("DOTLAYER_PROFILE")
  end

  def test_whitespace_command_output_falls_back_to_desktop
    config = stub_config(
      profile_detect: "echo '   '",
      profile_env: "DOTLAYER_TEST_NONEXISTENT"
    )

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    assert_equal "desktop", detection.profile
  end
end
