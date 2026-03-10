require "test_helper"

class ConfigTest < Minitest::Test
  def test_defaults_without_config_file
    config = Dotlayer::Config.new

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
    config = Dotlayer::Config.new
    repos = config.repos

    assert_equal 1, repos.size
    assert_equal File.expand_path("~/.public_dotfiles"), repos.first["path"]
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
      assert_equal File.expand_path("~/.dotfiles"), config.repos[0]["path"]
      assert_equal true, config.repos[1]["private"]
    end
  end
end
