require "yaml"

module Dotlayer
  Repo = Data.define(:path, :private, :packages)

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
      @data = load_config
    end

    def target
      File.expand_path(@data.fetch("target", "~"))
    end

    def repos
      @repos ||= @data.fetch("repos", [{ "path" => "~/.public_dotfiles" }]).filter_map do |entry|
        path = entry["path"]&.to_s
        next if path.nil? || path.empty?

        Repo.new(
          path: File.expand_path(path),
          private: entry["private"] || false,
          packages: entry["packages"]&.freeze
        )
      end.freeze
    end

    def packages
      @packages ||= @data.fetch("packages") { DEFAULT_PACKAGES }.freeze
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

    def load_config
      return {} unless @path && File.exist?(@path)

      data = YAML.safe_load_file(@path, permitted_classes: [Symbol]) || {}
      return data if data.is_a?(Hash)

      abort "Error: #{@path} must contain a YAML mapping, got #{data.class}"
    rescue Psych::SyntaxError => e
      abort "Error: invalid YAML in #{@path}: #{e.message}"
    end

    def discover_config
      DEFAULT_CONFIG_PATHS
        .map { |p| File.expand_path(p) }
        .find { |p| File.exist?(p) }
    end
  end
end
