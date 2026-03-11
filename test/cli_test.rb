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
end
