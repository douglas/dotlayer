require "test_helper"

class ResolverTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_resolves_base_packages
    create_dirs("stow", "bin", "git", "zsh", "config")
    config = config_with_repo(@tmpdir)
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [])

    resolver = Dotlayer::Resolver.new(config: config, detection: detection)
    packages = resolver.resolve.map(&:last)

    assert_equal %w[stow bin git zsh config], packages
  end

  def test_resolves_os_layer
    create_dirs("config", "config-linux", "config-macos")
    config = config_with_repo(@tmpdir, packages: %w[config])
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [])

    resolver = Dotlayer::Resolver.new(config: config, detection: detection)
    packages = resolver.resolve.map(&:last)

    assert_includes packages, "config-linux"
    refute_includes packages, "config-macos"
  end

  def test_resolves_distro_layer
    create_dirs("config", "config-omarchy", "config-fedora")
    config = config_with_repo(@tmpdir, packages: %w[config])
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: ["omarchy"])

    resolver = Dotlayer::Resolver.new(config: config, detection: detection)
    packages = resolver.resolve.map(&:last)

    assert_includes packages, "config-omarchy"
    refute_includes packages, "config-fedora"
  end

  def test_resolves_distro_profile_layer
    create_dirs("config", "config-omarchy", "config-omarchy-desktop", "config-omarchy-laptop")
    config = config_with_repo(@tmpdir, packages: %w[config])
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: ["omarchy"])

    resolver = Dotlayer::Resolver.new(config: config, detection: detection)
    packages = resolver.resolve.map(&:last)

    assert_includes packages, "config-omarchy-desktop"
    refute_includes packages, "config-omarchy-laptop"
  end

  def test_layer_order_is_os_then_distro_then_distro_profile
    create_dirs("config", "config-linux", "config-omarchy", "config-omarchy-desktop")
    config = config_with_repo(@tmpdir, packages: %w[config])
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: ["omarchy"])

    resolver = Dotlayer::Resolver.new(config: config, detection: detection)
    packages = resolver.resolve.map(&:last)

    linux_idx = packages.index("config-linux")
    omarchy_idx = packages.index("config-omarchy")
    desktop_idx = packages.index("config-omarchy-desktop")

    assert linux_idx < omarchy_idx, "OS layer should come before distro"
    assert omarchy_idx < desktop_idx, "Framework should come before distro+profile"
  end

  def test_skips_nonexistent_base_packages
    create_dirs("config")
    config = config_with_repo(@tmpdir, packages: %w[stow config])
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: [])

    resolver = Dotlayer::Resolver.new(config: config, detection: detection)
    packages = resolver.resolve.map(&:last)

    assert_equal %w[config], packages
  end

  def test_multiple_distros
    create_dirs("config", "config-omarchy", "config-omarchy-desktop", "config-fedora-desktop")
    config = config_with_repo(@tmpdir, packages: %w[config])
    detection = Dotlayer::Detection.new(os: "linux", profile: "desktop", distros: %w[omarchy fedora])

    resolver = Dotlayer::Resolver.new(config: config, detection: detection)
    packages = resolver.resolve.map(&:last)

    assert_includes packages, "config-omarchy"
    assert_includes packages, "config-omarchy-desktop"
    assert_includes packages, "config-fedora-desktop"
  end

  private

  def create_dirs(*names)
    names.each { |n| FileUtils.mkdir_p(File.join(@tmpdir, n)) }
  end

  def config_with_repo(path, packages: nil)
    config = Dotlayer::Config.new
    config.define_singleton_method(:repos) { [{ "path" => path }] }
    config.define_singleton_method(:packages) { packages } if packages
    config
  end
end
