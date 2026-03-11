require "test_helper"

class ConfigTest < Minitest::Test
  def test_defaults_without_config_file
    config = Dotlayer::Config.new("/nonexistent/dotlayer.yml")

    assert_equal File.expand_path("~"), config.target
    assert_equal %w[stow bin git zsh config], config.packages
    assert_equal "hostnamectl chassis", config.profile_detect
    assert_equal "DOTLAYER_PROFILE", config.profile_env
    assert_equal({}, config.distros)
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
      assert_equal({ "omarchy" => { "detect" => "command -v omarchy" } }, config.distros)
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
      YAML

      config = Dotlayer::Config.new(config_path)

      assert_equal({ "mycompany" => { "detect" => "test -d ~/src/mycompany" } }, config.groups)
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

      assert_equal({ "after_system_files" => ["echo done"] }, config.hooks)
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
end
