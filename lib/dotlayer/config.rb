require "yaml"

module Dotlayer
  # targets maps explicitly listed package names to their own target
  # (already expanded); packages without an entry use the global target.
  Repo = Data.define(:path, :private, :packages, :standalone_packages, :group_packages, :targets) do
    def initialize(targets: {}, **rest)
      super
    end
  end

  class Config
    DEFAULT_PACKAGES = %w[stow bin git zsh config].freeze
    PACKAGE_KEYS = %w[name target].freeze
    ENV_CONFIG = "DOTLAYER_CONFIG".freeze
    # Checked in order, after $DOTLAYER_CONFIG. The two dotfiles-repo paths are
    # where a stowed ~/.config/dotlayer/dotlayer.yml lives before it is linked.
    DEFAULT_CONFIG_PATHS = %w[
      ~/.config/dotlayer/dotlayer.yml
      ~/.private_dotfiles/config/.config/dotlayer/dotlayer.yml
      ~/.public_dotfiles/config/.config/dotlayer/dotlayer.yml
      ~/.public_dotfiles/dotlayer.yml
      ~/.dotfiles/dotlayer.yml
    ].freeze

    attr_reader :path, :source

    def initialize(path = nil)
      @source = path ? "-c" : nil
      @path = path || discover_config
      @data = load_config
      validate_packages
      validate_machines
    end

    def target
      File.expand_path(@data.fetch("target", "~"))
    end

    def repos
      @repos ||= @data.fetch("repos", [{"path" => "~/.public_dotfiles"}]).filter_map do |entry|
        path = entry["path"]&.to_s
        next if path.nil? || path.empty?

        build_repo(entry, path)
      end.freeze
    end

    def packages
      top_level_packages.first
    end

    # Targets set on top-level `packages:` entries, by package name.
    def package_targets
      top_level_packages.last
    end

    # Where stow links a package: its own `target:` when it is listed with
    # one, else (for a layered variant that is not listed itself, such as
    # config-linux) the target of its base package, else the global target.
    def target_for(repo_path, package)
      repo = repos.find { |r| r.path == repo_path }
      return target unless repo

      targets = (repo.packages ? {} : package_targets).merge(repo.targets)
      bases = repo.packages || packages
      listed = bases + Array(repo.standalone_packages) + repo.group_packages.values.flatten
      return targets.fetch(package, target) if listed.include?(package)

      base = bases.select { |b| targets.key?(b) && package.start_with?("#{b}-") }.max_by(&:length)
      base ? targets[base] : target
    end

    def profile_detect
      @data.dig("profiles", "detect") || "hostnamectl chassis"
    end

    # False when profiles: has no detect, so the detector uses DMI chassis_type.
    def profile_detect_configured?
      !@data.dig("profiles", "detect").nil?
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

    def machines
      @data.fetch("machines", {})
    end

    def machine_env
      @data.dig("machines", "env") || "DOTLAYER_MACHINE"
    end

    def system_files
      @data.fetch("system_files", [])
    end

    def hooks
      @data.fetch("hooks", {})
    end

    private

    # Parse package lists now, so a bad entry fails the command up front.
    def validate_packages
      packages
      repos
    end

    # Each machine rule needs exactly one of detect: (shell) or model: (text).
    def validate_machines
      machines.each do |name, entry|
        next if name == "env"

        unless entry.is_a?(Hash)
          abort "Error: machine #{name} in #{@path} must be a mapping with detect: or model:"
        end
        both = entry.key?("detect") && entry.key?("model")
        abort "Error: machine #{name} in #{@path} has both detect: and model:, use one" if both
        abort "Error: machine #{name} in #{@path} needs detect: or model:" unless entry.key?("detect") || entry.key?("model")

        patterns = entry["model"]
        next unless entry.key?("model")

        valid = (patterns.is_a?(String) && !patterns.empty?) ||
          (patterns.is_a?(Array) && patterns.any? && patterns.all? { |p| p.is_a?(String) && !p.empty? })
        abort "Error: machine #{name} in #{@path}: model: must be a string or a list of strings" unless valid
      end
    end

    def top_level_packages
      @top_level_packages ||= begin
        names, targets = parse_packages(@data.fetch("packages") { DEFAULT_PACKAGES }, "packages")
        [names.freeze, targets.freeze]
      end
    end

    def build_repo(entry, path)
      targets = {}
      packages, base_targets = parse_packages(entry["packages"], "repo #{path} packages")
      standalone, standalone_targets = parse_packages(entry["standalone_packages"], "repo #{path} standalone_packages")
      groups = (entry["group_packages"] || {}).to_h do |group, list|
        names, group_targets = parse_packages(list, "repo #{path} group_packages.#{group}")
        targets.merge!(group_targets)
        [group, names]
      end
      targets.merge!(base_targets, standalone_targets)

      Repo.new(
        path: File.expand_path(path),
        private: entry["private"] || false,
        packages: packages&.freeze,
        standalone_packages: standalone&.freeze,
        group_packages: groups,
        targets:
      )
    end

    # A package entry is a name, or {name:, target:}. Returns the names (nil
    # when the list is absent) and a {name => expanded target} hash.
    def parse_packages(list, where)
      return [nil, {}] if list.nil?

      abort "Error: #{where} in #{@path} must be a list" unless list.is_a?(Array)

      targets = {}
      names = list.map do |entry|
        name, target = parse_package(entry, where)
        targets[name] = target if target
        name
      end
      [names, targets]
    end

    def parse_package(entry, where)
      return [entry, nil] if entry.is_a?(String) && !entry.empty?

      unless entry.is_a?(Hash)
        abort "Error: #{where} in #{@path}: each package must be a name or a {name:, target:} mapping, got #{entry.inspect}"
      end

      unknown = entry.keys - PACKAGE_KEYS
      abort "Error: #{where} in #{@path}: unknown package key(s) #{unknown.join(", ")} (allowed: #{PACKAGE_KEYS.join(", ")})" if unknown.any?

      name = entry["name"]
      abort "Error: #{where} in #{@path}: package #{entry.inspect} needs a name" unless name.is_a?(String) && !name.empty?

      target = entry["target"]
      return [name, nil] if target.nil?

      abort "Error: #{where} in #{@path}: target for #{name} must be a non-empty path" unless target.is_a?(String) && !target.empty?

      [name, File.expand_path(target)]
    end

    def load_config
      return {} unless @path && File.exist?(@path)

      data = YAML.safe_load_file(@path, permitted_classes: [Symbol]) || {}
      return data if data.is_a?(Hash)

      abort "Error: #{@path} must contain a YAML mapping, got #{data.class}"
    rescue Psych::SyntaxError => e
      abort "Error: invalid YAML in #{@path}: #{e.message}"
    end

    def discover_config
      from_env = ENV[ENV_CONFIG].to_s
      if !from_env.empty? && File.exist?(File.expand_path(from_env))
        @source = "$#{ENV_CONFIG}"
        return File.expand_path(from_env)
      end

      @source = "discovered"
      DEFAULT_CONFIG_PATHS
        .map { |p| File.expand_path(p) }
        .find { |p| File.exist?(p) }
    end
  end
end
