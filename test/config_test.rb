require "test_helper"

class ConfigTest < Minitest::Test
  def test_defaults_without_config_file
    config = Dotlayer::Config.new("/nonexistent/dotlayer.yml")

    assert_equal File.expand_path("~"), config.target
    assert_equal %w[stow bin git zsh config], config.packages
    assert_equal "hostnamectl chassis", config.profile_detect
    assert_equal "DOTLAYER_PROFILE", config.profile_env
    assert_equal "DOTLAYER_MACHINE", config.machine_env
    assert_equal({}, config.distros)
    assert_equal({}, config.groups)
    assert_equal({}, config.machines)
    assert_equal({}, config.hooks)
    assert_equal [], config.system_files
  end

  def test_loads_yaml_config
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "dotlayer.yml")
      File.write(config_path, <<~YAML)
        target: ~/test-home
        packages:
          - stow
          - config
        profiles:
          detect: echo laptop
          env: MY_PROFILE
        distros:
          omarchy:
            detect: command -v omarchy
      YAML

      config = Dotlayer::Config.new(config_path)

      assert_equal File.expand_path("~/test-home"), config.target
      assert_equal %w[stow config], config.packages
      assert_equal "echo laptop", config.profile_detect
      assert_equal "MY_PROFILE", config.profile_env
      assert_equal({"omarchy" => {"detect" => "command -v omarchy"}}, config.distros)
    end
  end

  def test_repos_default
    config = Dotlayer::Config.new("/nonexistent/dotlayer.yml")
    repos = config.repos

    assert_equal 1, repos.size
    assert_equal File.expand_path("~/.public_dotfiles"), repos.first.path
  end

  def test_repos_from_config
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "dotlayer.yml")
      File.write(config_path, <<~YAML)
        repos:
          - path: ~/.dotfiles
          - path: ~/.private_dotfiles
            private: true
      YAML

      config = Dotlayer::Config.new(config_path)

      assert_equal 2, config.repos.size
      assert_equal File.expand_path("~/.dotfiles"), config.repos[0].path
      assert_equal false, config.repos[0].private
      assert_equal true, config.repos[1].private
      assert_nil config.repos[0].packages
    end
  end

  def test_invalid_yaml_aborts
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "dotlayer.yml")
      File.write(config_path, "{ invalid yaml :::")

      assert_raises(SystemExit) do
        capture_io { Dotlayer::Config.new(config_path) }
      end
    end
  end

  def test_non_hash_yaml_aborts
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "dotlayer.yml")
      File.write(config_path, "- just\n- a\n- list\n")

      assert_raises(SystemExit) do
        capture_io { Dotlayer::Config.new(config_path) }
      end
    end
  end

  def test_groups_from_config
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "dotlayer.yml")
      File.write(config_path, <<~YAML)
        groups:
          mycompany:
            detect: test -d ~/src/mycompany
        machines:
          env: MY_MACHINE
          t14:
            detect: model="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"; case "$model" in *T14*) exit 0 ;; *) exit 1 ;; esac
      YAML

      config = Dotlayer::Config.new(config_path)

      assert_equal({"mycompany" => {"detect" => "test -d ~/src/mycompany"}}, config.groups)
      assert_equal "MY_MACHINE", config.machine_env
      assert_equal(
        {
          "env" => "MY_MACHINE",
          "t14" => {
            "detect" => 'model="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"; case "$model" in *T14*) exit 0 ;; *) exit 1 ;; esac'
          }
        },
        config.machines
      )
    end
  end

  def test_hooks_from_config
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "dotlayer.yml")
      File.write(config_path, <<~YAML)
        hooks:
          after_system_files:
            - echo done
      YAML

      config = Dotlayer::Config.new(config_path)

      assert_equal({"after_system_files" => ["echo done"]}, config.hooks)
    end
  end

  def test_repos_with_per_repo_packages
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "dotlayer.yml")
      File.write(config_path, <<~YAML)
        repos:
          - path: ~/.dotfiles
            packages:
              - config
              - fonts
            standalone_packages:
              - bin
            group_packages:
              mycompany:
                - mycompany
      YAML

      config = Dotlayer::Config.new(config_path)

      assert_equal %w[config fonts], config.repos[0].packages
      assert_equal %w[bin], config.repos[0].standalone_packages
      assert_equal({"mycompany" => ["mycompany"]}, config.repos[0].group_packages)
    end
  end

  def test_system_files_from_config
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "dotlayer.yml")
      File.write(config_path, <<~YAML)
        system_files:
          - source: config-linux/etc/udev/rules.d/70-keychron.rules
            dest: /etc/udev/rules.d/70-keychron.rules
            mode: "0644"
      YAML

      config = Dotlayer::Config.new(config_path)

      assert_equal 1, config.system_files.size
      assert_equal "/etc/udev/rules.d/70-keychron.rules", config.system_files[0]["dest"]
      assert_equal "0644", config.system_files[0]["mode"]
    end
  end

  def test_repos_filters_nil_and_empty_paths
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "dotlayer.yml")
      File.write(config_path, <<~YAML)
        repos:
          - path:
          - path: ""
          - path: ~/.dotfiles
      YAML

      config = Dotlayer::Config.new(config_path)

      assert_equal 1, config.repos.size
      assert_equal File.expand_path("~/.dotfiles"), config.repos[0].path
    end
  end

  def test_packages_accept_names_and_hashes_with_targets
    config = load_config(<<~YAML)
      target: /home/me
      packages:
        - config
        - name: codex
          target: /home/me/.codex
        - name: plain
    YAML

    assert_equal %w[config codex plain], config.packages
    assert_equal({"codex" => "/home/me/.codex"}, config.package_targets)
  end

  def test_repo_package_lists_accept_hashes
    config = load_config(<<~YAML)
      repos:
        - path: /repo
          packages:
            - config
            - {name: codex, target: /t/codex}
          standalone_packages:
            - {name: bin, target: /t/bin}
          group_packages:
            work:
              - {name: work, target: /t/work}
              - other
    YAML

    repo = config.repos.first
    assert_equal %w[config codex], repo.packages
    assert_equal %w[bin], repo.standalone_packages
    assert_equal({"work" => %w[work other]}, repo.group_packages)
    assert_equal({"codex" => "/t/codex", "bin" => "/t/bin", "work" => "/t/work"}, repo.targets)
  end

  def test_target_for_uses_package_target_global_target_and_base_target_for_variants
    config = load_config(<<~YAML)
      target: /home/me
      repos:
        - path: /repo
          packages:
            - config
            - {name: codex, target: /home/me/.codex}
            - codex-agents
          standalone_packages:
            - {name: bin, target: /home/me/.bin}
    YAML

    assert_equal "/home/me", config.target_for("/repo", "config")
    assert_equal "/home/me/.codex", config.target_for("/repo", "codex")
    # Variants found by convention inherit the base package's target.
    assert_equal "/home/me/.codex", config.target_for("/repo", "codex-linux")
    # A package that is listed itself does not inherit from a prefix.
    assert_equal "/home/me", config.target_for("/repo", "codex-agents")
    assert_equal "/home/me/.bin", config.target_for("/repo", "bin")
    assert_equal "/home/me", config.target_for("/elsewhere", "codex")
  end

  def test_target_for_uses_top_level_package_targets_for_repos_without_packages
    config = load_config(<<~YAML)
      target: /home/me
      repos:
        - path: /repo
      packages:
        - {name: config, target: /t/config}
    YAML

    assert_equal "/t/config", config.target_for("/repo", "config")
    assert_equal "/t/config", config.target_for("/repo", "config-linux")
    assert_equal "/home/me", config.target_for("/repo", "other")
  end

  def test_string_packages_keep_the_global_target
    config = load_config("target: /home/me\npackages: [config]\n")

    assert_equal "/home/me", config.target_for(config.repos.first.path, "config")
    assert_empty config.package_targets
  end

  def test_invalid_package_entries_abort_with_a_clear_message
    {
      "packages:\n  - {target: /t}\n" => /needs a name/,
      "packages:\n  - {name: a, path: /t}\n" => /unknown package key\(s\) path/,
      "packages:\n  - {name: a, target: ''}\n" => /target for a must be a non-empty path/,
      "packages:\n  - 42\n" => /name or a \{name:, target:\}/,
      "repos:\n  - path: /r\n    standalone_packages:\n      - {name: a, tgt: /t}\n" => /standalone_packages.*unknown package key/
    }.each do |yaml, message|
      error = nil
      stderr = capture_io { error = assert_raises(SystemExit) { load_config(yaml) } }.last

      assert_equal 1, error.status
      assert_match(message, stderr)
    end
  end

  def test_machine_rules_accept_detect_or_model
    config = load_config(<<~YAML)
      machines:
        env: MY_MACHINE
        a:
          detect: "true"
        b:
          model: ThinkPad T14
        c:
          model: [one, two]
    YAML

    assert_equal %w[env a b c], config.machines.keys
  end

  def test_machine_rule_errors
    {
      "machines:\n  a:\n    detect: 'true'\n    model: x\n" => /has both detect: and model:/,
      "machines:\n  a: {}\n" => /needs detect: or model:/,
      "machines:\n  a:\n    model: ''\n" => /model: must be a string or a list of strings/,
      "machines:\n  a:\n    model: [1]\n" => /model: must be a string or a list of strings/,
      "machines:\n  a: nope\n" => /must be a mapping/
    }.each do |yaml, message|
      stderr = capture_io { assert_raises(SystemExit) { load_config(yaml) } }.last

      assert_match(message, stderr)
    end
  end

  def test_profile_detect_configured
    assert load_config("profiles:\n  detect: echo laptop\n").profile_detect_configured?
    refute load_config("profiles: {env: X}\n").profile_detect_configured?
  end

  def test_discovery_order
    with_home do |home|
      write_config(home, ".public_dotfiles/config/.config/dotlayer/dotlayer.yml", "target: /public\n")
      assert_equal "/public", Dotlayer::Config.new.target
      assert_equal "discovered", Dotlayer::Config.new.source

      write_config(home, ".private_dotfiles/config/.config/dotlayer/dotlayer.yml", "target: /private\n")
      assert_equal "/private", Dotlayer::Config.new.target

      write_config(home, ".config/dotlayer/dotlayer.yml", "target: /stowed\n")
      assert_equal "/stowed", Dotlayer::Config.new.target
      assert_equal File.join(home, ".config/dotlayer/dotlayer.yml"), Dotlayer::Config.new.path
    end
  end

  def test_env_var_is_checked_first
    with_home do |home|
      write_config(home, ".config/dotlayer/dotlayer.yml", "target: /stowed\n")
      custom = write_config(home, "custom.yml", "target: /custom\n")
      ENV["DOTLAYER_CONFIG"] = custom

      config = Dotlayer::Config.new

      assert_equal "/custom", config.target
      assert_equal "$DOTLAYER_CONFIG", config.source
    end
  end

  def test_env_var_pointing_nowhere_falls_through
    with_home do |home|
      write_config(home, ".config/dotlayer/dotlayer.yml", "target: /stowed\n")
      ENV["DOTLAYER_CONFIG"] = File.join(home, "missing.yml")

      assert_equal "/stowed", Dotlayer::Config.new.target
    end
  end

  def test_explicit_path_wins_and_is_labelled
    with_home do |home|
      write_config(home, ".config/dotlayer/dotlayer.yml", "target: /stowed\n")
      custom = write_config(home, "custom.yml", "target: /custom\n")

      config = Dotlayer::Config.new(custom)

      assert_equal "/custom", config.target
      assert_equal "-c", config.source
    end
  end

  private

  def load_config(yaml)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "dotlayer.yml")
      File.write(path, yaml)
      Dotlayer::Config.new(path)
    end
  end

  def with_home
    Dir.mktmpdir do |home|
      original = ENV.values_at("HOME", "DOTLAYER_CONFIG")
      ENV["HOME"] = home
      ENV.delete("DOTLAYER_CONFIG")
      yield home
    ensure
      ENV["HOME"], config_env = original
      config_env ? ENV["DOTLAYER_CONFIG"] = config_env : ENV.delete("DOTLAYER_CONFIG")
    end
  end

  def write_config(home, relative, text)
    path = File.join(home, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    path
  end
end
