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

  def test_detection_is_immutable
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: ["omarchy"], groups: ["mycompany"])

    assert_equal "linux", detection.os
    assert_equal "desktop", detection.profile
    assert_equal ["omarchy"], detection.distros
    assert_equal ["mycompany"], detection.groups
    assert_raises(NoMethodError) { detection.os = "macos" }
  end

  def test_detect_distro_with_command
    config = stub_config(distros: { "test_distro" => { "detect" => "true" } })

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    assert_includes detection.distros, "test_distro"
  end

  def test_detect_distro_not_found
    config = stub_config(distros: { "missing_distro" => { "detect" => "false" } })

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    refute_includes detection.distros, "missing_distro"
  end

  def test_detect_group_with_command
    config = stub_config(groups: { "mycompany" => { "detect" => "true" } })

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    assert_includes detection.groups, "mycompany"
  end

  def test_detect_group_not_found
    config = stub_config(groups: { "acme" => { "detect" => "false" } })

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

  def test_empty_detect_command_skips_distro
    config = stub_config(distros: { "broken" => { "detect" => "" } })

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    refute_includes detection.distros, "broken"
  end

  def test_nil_detect_command_skips_distro
    config = stub_config(distros: { "broken" => {} })

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    refute_includes detection.distros, "broken"
  end

  def test_empty_profile_detect_falls_back_to_desktop
    config = stub_config(profile_detect: "", profile_env: "DOTLAYER_TEST_NONEXISTENT")

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    assert_equal "desktop", detection.profile
  end

  def test_detect_os_macos
    detector = Dotlayer::Detector.new(config: Dotlayer::Config.new)
    detector.define_singleton_method(:detect) do
      os = case "darwin23.0"
           when /darwin/ then "macos"
           when /linux/  then "linux"
           else "unknown"
           end
      Dotlayer::Detection.new(os: os, profile: "desktop", distros: [], groups: [])
    end
    detection = detector.detect

    assert_equal "macos", detection.os
  end

  def test_detect_os_unknown
    detector = Dotlayer::Detector.new(config: Dotlayer::Config.new)
    detector.define_singleton_method(:detect) do
      os = case "freebsd14"
           when /darwin/ then "macos"
           when /linux/  then "linux"
           else "unknown"
           end
      Dotlayer::Detection.new(os: os, profile: "desktop", distros: [], groups: [])
    end
    detection = detector.detect

    assert_equal "unknown", detection.os
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

  def test_non_string_detect_skips_distro
    config = stub_config(distros: { "broken" => { "detect" => 42 } })

    detector = Dotlayer::Detector.new(config: config)
    detection = detector.detect

    refute_includes detection.distros, "broken"
  end
end
