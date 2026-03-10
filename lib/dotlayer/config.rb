require "yaml"
require "pathname"

module Dotlayer
  class Config
    DEFAULT_PACKAGES = %w[stow bin git zsh config].freeze

    attr_reader :path

    def initialize(path = nil)
      @path = path
      @data = path && File.exist?(path) ? YAML.load_file(path) : {}
    end

    def target
      File.expand_path(@data.fetch("target", "~"))
    end

    def repos
      @data.fetch("repos", [{ "path" => "~/.public_dotfiles" }]).map do |repo|
        repo.merge("path" => File.expand_path(repo["path"]))
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

    def system_files
      @data.fetch("system_files", [])
    end

    def hooks
      @data.fetch("hooks", {})
    end
  end
end
