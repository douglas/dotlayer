require "test_helper"

class CLITest < Minitest::Test
  def test_version_command
    output = capture_io { Dotlayer::CLI.new.run(["version"]) }.first
    assert_match(/dotlayer \d+\.\d+\.\d+/, output)
  end

  def test_version_flag
    output = capture_io { Dotlayer::CLI.new.run(["--version"]) }.first
    assert_match(/dotlayer \d+\.\d+\.\d+/, output)
  end

  def test_unknown_command_shows_usage
    output = capture_io { Dotlayer::CLI.new.run(["nonsense"]) }.first
    assert_match(/Usage:/, output)
  end

  def test_no_command_shows_usage
    output = capture_io { Dotlayer::CLI.new.run([]) }.first
    assert_match(/Usage:/, output)
  end

  def test_adopt_without_args_aborts
    assert_raises(SystemExit) do
      capture_io { Dotlayer::CLI.new.run(["adopt"]) }
    end
  end

  def test_adopt_with_only_package_aborts
    assert_raises(SystemExit) do
      capture_io { Dotlayer::CLI.new.run(["adopt", "config"]) }
    end
  end

  def test_status_routes_without_error
    output = capture_io {
      Dotlayer::CLI.new.run(["-c", "/nonexistent/dotlayer.yml", "status"])
    }.first

    assert_match(/OS:/, output)
    assert_match(/Profile:/, output)
  end

  def test_doctor_routes_without_error
    output = capture_io {
      Dotlayer::CLI.new.run(["-c", "/nonexistent/dotlayer.yml", "doctor"])
    }.first

    assert_match(/Doctor/, output)
  end

  def test_dry_run_flag_forwarded_to_install
    output = capture_io {
      Dotlayer::CLI.new.run(["-c", "/nonexistent/dotlayer.yml", "-n", "install"])
    }.first

    assert_match(/dry-run/, output)
  end
end
