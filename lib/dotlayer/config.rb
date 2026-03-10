require "yaml"
require "pathname"

module Dotlayer
  class Config
    DEFAULT_PACKAGES = %w[stow bin git zsh config].freeze
    DEFAULT_CONFIG_PATHS = %w[
      ~/.config/dotlayer/dotlayer.yml
      ~/.public_dotfiles/dotlayer.yml
      ~/.dotfiles/dotlayer.yml
    ].freeze

    attr_reader :path

    def initialize(path = nil)
      @path = path || discover_config
      @data = @path && File.exist?(@path) ? YAML.load_file(@path) : {}
    end

    def target
      File.expand_path(@data.fetch("target", "~"))
    end

    def repos
      @data.fetch("repos", [{ "path" => "~/.public_dotfiles" }]).map do |repo|
        expanded = repo.merge("path" => File.expand_path(repo["path"]))
        expanded["packages"] = repo["packages"] if repo["packages"]
        expanded
      end
    end

    def packages
      @data.fetch("packages", DEFAULT_PACKAGES)
    end

    def profile_detect
      @data.dig("profiles", "detect") || "hostnamectl chassis"
    end

    def profile_env
      @data.dig("profiles", "env") || "DOTLAYER_PROFILE"
    end

    def distros
      @data.fetch("distros", {})
    end

    def groups
      @data.fetch("groups", {})
    end

    def system_files
      @data.fetch("system_files", [])
    end

    def hooks
      @data.fetch("hooks", {})
    end

    private

    def discover_config
      DEFAULT_CONFIG_PATHS
        .map { |p| File.expand_path(p) }
        .find { |p| File.exist?(p) }
    end
  end
end
