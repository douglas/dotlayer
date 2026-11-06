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
    Dir.mktmpdir do |dir|
      repo = File.join(dir, "repo")
      FileUtils.mkdir_p([File.join(repo, "config"), File.join(dir, "home")])
      config_path = File.join(dir, "dotlayer.yml")
      File.write(config_path, "target: #{dir}/home\nrepos:\n  - path: #{repo}\npackages:\n  - config\n")

      output = capture_io {
        Dotlayer::CLI.new.run(["-c", config_path, "doctor"])
      }.first

      assert_match(/Doctor/, output)
    end
  end

  def test_doctor_exits_1_when_issues_found
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "dotlayer.yml")
      File.write(config_path, "target: #{dir}\nrepos:\n  - path: #{dir}/missing\n")

      error = assert_raises(SystemExit) {
        capture_io { Dotlayer::CLI.new.run(["-c", config_path, "--depth", "2", "doctor"]) }
      }

      assert_equal 1, error.status
    end
  end

  def test_dry_run_flag_forwarded_to_install
    Dir.mktmpdir do |dir|
      repo = File.join(dir, "repo")
      target = File.join(dir, "home")
      config_path = File.join(dir, "dotlayer.yml")
      FileUtils.mkdir_p([File.join(repo, "config"), target])
      File.write(config_path, <<~YAML)
        target: #{target}
        repos:
          - path: #{repo}
        packages:
          - config
      YAML

      output = capture_io {
        Dotlayer::CLI.new.run(["-c", config_path, "-n", "install"])
      }.first

      assert_match(/dry-run/, output)
    end
  end

  def test_verbose_says_which_config_was_used
    Dir.mktmpdir do |dir|
      path = File.join(dir, "dotlayer.yml")
      File.write(path, "repos: []\n")

      error = capture_io { Dotlayer::CLI.new.run(["-v", "-c", path, "status"]) }.last

      assert_match(/Using config: #{Regexp.escape(path)} \(-c\)/, error)
    end
  end

  def test_install_yes_installs_system_files_and_without_it_asks_for_yes
    skip "system files are Linux only" unless RbConfig::CONFIG["host_os"].match?(/linux/)

    with_install_fixture do |dir, config_path|
      dest = File.join(dir, "etc", "test.conf")
      $stdin = StringIO.new("")

      output = capture_io { Dotlayer::CLI.new.run(["-c", config_path, "install"]) }.first

      assert_match(/1 system file\(s\) need installing.*--yes/, output)
      refute File.exist?(dest)

      capture_io { Dotlayer::CLI.new.run(["-c", config_path, "install", "--yes"]) }

      assert_equal "sys", File.read(dest)
    end
  ensure
    $stdin = STDIN
  end

  def test_install_backup_moves_blocking_files_aside
    with_install_fixture do |dir, config_path|
      live = File.join(dir, "home", ".config", "app", "settings")
      FileUtils.mkdir_p(File.dirname(live))
      File.write(live, "mine")

      error = capture_io {
        assert_raises(SystemExit) { Dotlayer::CLI.new.run(["-c", config_path, "install"]) }
      }.first
      assert_match(/Rerun with --backup/, error)

      capture_io { Dotlayer::CLI.new.run(["-c", config_path, "install", "--backup", "--yes"]) }

      assert File.symlink?(live)
      moved = Dir.glob(File.join(dir, "home", "dotfiles-conflicts-*", ".config", "app", "settings"))
      assert_equal ["mine"], moved.map { |file| File.read(file) }
    end
  end

  def test_hooks_routes_and_validates_the_action
    assert_raises(SystemExit) { capture_io { Dotlayer::CLI.new.run(["-c", "/nonexistent/dotlayer.yml", "hooks", "bogus"]) } }

    Dir.mktmpdir do |dir|
      path = File.join(dir, "dotlayer.yml")
      File.write(path, "repos:\n  - path: #{dir}/dots\n")
      system("git", "init", "-q", "#{dir}/dots")

      capture_io { Dotlayer::CLI.new.run(["-c", path, "hooks", "install"]) }

      assert File.exist?("#{dir}/dots/.git/hooks/post-merge")
    end
  end

  private

  # A repo with a config package and one system file, a fake sudo that just
  # runs its arguments, and a temp HOME so stow reads no real ignore list.
  def with_install_fixture
    Dir.mktmpdir do |dir|
      repo = File.join(dir, "repo")
      FileUtils.mkdir_p([File.join(repo, "config", ".config", "app"), File.join(repo, "sys"), File.join(dir, "home"), File.join(dir, "bin")])
      File.write(File.join(repo, "config", ".config", "app", "settings"), "repo")
      File.write(File.join(repo, "sys", "test.conf"), "sys")
      File.write(File.join(dir, "bin", "sudo"), "#!/bin/sh\nexec \"$@\"\n")
      File.chmod(0o755, File.join(dir, "bin", "sudo"))
      config_path = File.join(dir, "dotlayer.yml")
      File.write(config_path, <<~YAML)
        target: #{dir}/home
        repos:
          - path: #{repo}
        packages: [config]
        system_files:
          - source: sys/test.conf
            dest: #{dir}/etc/test.conf
      YAML

      original = ENV.values_at("PATH", "HOME")
      ENV["PATH"] = "#{dir}/bin:#{original[0]}"
      ENV["HOME"] = dir
      yield dir, config_path
    ensure
      ENV["PATH"], ENV["HOME"] = original
    end
  end
end
