require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "dotlayer"

module TestConfigHelper
  NOT_SET = Object.new

  def stub_config(target: nil, repos: NOT_SET, packages: nil, **overrides)
    config = Dotlayer::Config.new("/nonexistent/dotlayer.yml")
    config.define_singleton_method(:target) { target } if target
    config.define_singleton_method(:repos) { repos } unless repos.equal?(NOT_SET)
    config.define_singleton_method(:packages) { packages } if packages
    overrides.each do |method, value|
      config.define_singleton_method(method) { value }
    end
    config
  end

  def build_repo(path:, private: false, packages: nil, standalone_packages: nil, group_packages: {})
    Dotlayer::Repo.new(path:, private:, packages:, standalone_packages:, group_packages:)
  end

  def build_detection(os: "linux", profile: "desktop", machine: "test-machine", distros: [], groups: [])
    Dotlayer::Detection.new(os:, profile:, machine:, distros:, groups:)
  end

  def stub_detector(detection = build_detection)
    detector = Object.new
    detector.define_singleton_method(:detect) { detection }
    detector
  end
end
