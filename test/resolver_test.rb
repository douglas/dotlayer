require "test_helper"

class ResolverTest < Minitest::Test
  include TestConfigHelper

  def setup
    @tmpdir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_resolves_base_packages
    create_dirs("stow", "bin", "git", "zsh", "config")
    config = stub_config(repos: [build_repo(path: @tmpdir)])
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [], groups: [])

    packages = resolve(config, detection)

    assert_equal %w[stow bin git zsh config], packages
  end

  def test_resolves_os_layer
    create_dirs("config", "config-linux", "config-macos")
    config = stub_config(repos: [build_repo(path: @tmpdir)], packages: %w[config])
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [], groups: [])

    packages = resolve(config, detection)

    assert_includes packages, "config-linux"
    refute_includes packages, "config-macos"
  end

  def test_resolves_distro_layer
    create_dirs("config", "config-omarchy", "config-fedora")
    config = stub_config(repos: [build_repo(path: @tmpdir)], packages: %w[config])
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: ["omarchy"], groups: [])

    packages = resolve(config, detection)

    assert_includes packages, "config-omarchy"
    refute_includes packages, "config-fedora"
  end

  def test_resolves_distro_profile_layer
    create_dirs("config", "config-omarchy", "config-omarchy-desktop", "config-omarchy-laptop")
    config = stub_config(repos: [build_repo(path: @tmpdir)], packages: %w[config])
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: ["omarchy"], groups: [])

    packages = resolve(config, detection)

    assert_includes packages, "config-omarchy-desktop"
    refute_includes packages, "config-omarchy-laptop"
  end

  def test_layer_order_is_os_then_distro_then_distro_profile
    create_dirs("config", "config-linux", "config-omarchy", "config-omarchy-desktop")
    config = stub_config(repos: [build_repo(path: @tmpdir)], packages: %w[config])
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: ["omarchy"], groups: [])

    packages = resolve(config, detection)

    linux_idx = packages.index("config-linux")
    omarchy_idx = packages.index("config-omarchy")
    desktop_idx = packages.index("config-omarchy-desktop")

    assert linux_idx < omarchy_idx, "OS layer should come before distro"
    assert omarchy_idx < desktop_idx, "Framework should come before distro+profile"
  end

  def test_skips_nonexistent_base_packages
    create_dirs("config")
    config = stub_config(repos: [build_repo(path: @tmpdir)], packages: %w[stow config])
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [], groups: [])

    packages = resolve(config, detection)

    assert_equal %w[config], packages
  end

  def test_multiple_distros
    create_dirs("config", "config-omarchy", "config-omarchy-desktop", "config-fedora-desktop")
    config = stub_config(repos: [build_repo(path: @tmpdir)], packages: %w[config])
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: %w[omarchy fedora], groups: [])

    packages = resolve(config, detection)

    assert_includes packages, "config-omarchy"
    assert_includes packages, "config-omarchy-desktop"
    assert_includes packages, "config-fedora-desktop"
  end

  def test_resolves_group_layer
    create_dirs("config", "config-mycompany", "config-acme")
    config = stub_config(repos: [build_repo(path: @tmpdir)], packages: %w[config])
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [], groups: ["mycompany"])

    packages = resolve(config, detection)

    assert_includes packages, "config-mycompany"
    refute_includes packages, "config-acme"
  end

  def test_groups_come_after_distro_profile_layers
    create_dirs("config", "config-linux", "config-omarchy", "config-omarchy-desktop", "config-mycompany")
    config = stub_config(repos: [build_repo(path: @tmpdir)], packages: %w[config])
    detection = Dotlayer::Detection.new(
      os: "linux", profile: "desktop", distros: ["omarchy"], groups: ["mycompany"]
    )

    packages = resolve(config, detection)

    desktop_idx = packages.index("config-omarchy-desktop")
    mycompany_idx = packages.index("config-mycompany")

    assert desktop_idx < mycompany_idx, "distro+profile should come before groups"
  end

  def test_per_repo_packages_override_global
    private_dir = Dir.mktmpdir
    create_dirs_in(private_dir, "config", "config-mycompany", "claude", "fonts")

    config = stub_config(
      repos: [build_repo(path: private_dir, private: true, packages: %w[config fonts])],
      packages: %w[stow bin git zsh config]
    )
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [], groups: ["mycompany"])

    packages = resolve(config, detection)

    assert_includes packages, "config"
    assert_includes packages, "fonts"
    assert_includes packages, "config-mycompany"
    assert_includes packages, "claude"
  ensure
    FileUtils.rm_rf(private_dir)
  end

  def test_standalone_dirs_in_layered_repo
    create_dirs("config", "config-linux", "claude", "scripts")
    config = stub_config(repos: [build_repo(path: @tmpdir)], packages: %w[config])
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [], groups: [])

    packages = resolve(config, detection)

    assert_equal %w[config config-linux claude scripts], packages
  end

  def test_stows_all_packages_from_repo_without_base_packages
    private_dir = Dir.mktmpdir
    create_dirs_in(private_dir, "claude", "fonts", "mycompany")
    create_dirs("config")

    config = stub_config(
      repos: [build_repo(path: @tmpdir), build_repo(path: private_dir)],
      packages: %w[config]
    )
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [], groups: [])
    resolver = Dotlayer::Resolver.new(config: config, detection: detection)
    packages = resolver.resolve

    assert_equal ["config"], packages.select { |r, _| r == @tmpdir }.map(&:last)

    private_packages = packages.select { |r, _| r == private_dir }.map(&:last)
    assert_equal %w[claude mycompany fonts], private_packages
  ensure
    FileUtils.rm_rf(private_dir)
  end

  private

  def resolve(config, detection)
    Dotlayer::Resolver.new(config: config, detection: detection).resolve.map(&:last)
  end

  def create_dirs_in(dir, *names)
    names.each { |n| FileUtils.mkdir_p(File.join(dir, n)) }
  end

  def create_dirs(*names)
    names.each { |n| FileUtils.mkdir_p(File.join(@tmpdir, n)) }
  end
end
