require "set"

module Dotlayer
  class Resolver
    def initialize(config:, detection:)
      @config = config
      @detection = detection
    end

    def resolve
      packages = []

      @config.repos.each do |repo|
        repo_path = repo["path"]
        next unless repo_path && Dir.exist?(repo_path)

        base_packages = repo["packages"] || @config.packages
        packages.concat(resolve_repo(repo_path, base_packages))
      end

      packages
    end

    private

    def resolve_repo(repo_path, base_packages)
      has_base_packages = base_packages.any? { |pkg| Dir.exist?(File.join(repo_path, pkg)) }

      if has_base_packages
        resolve_layered_repo(repo_path, base_packages)
      else
        resolve_all_packages(repo_path)
      end
    end

    # Repos with base packages use layered convention matching
    # plus standalone directories that don't match any layer pattern
    def resolve_layered_repo(repo_path, base_packages)
      packages = []

      base_packages.each do |pkg|
        packages << [repo_path, pkg] if Dir.exist?(File.join(repo_path, pkg))
      end

      dirs = top_level_dirs(repo_path)
      layers, matched_dirs = resolve_layers(repo_path, base_packages, dirs)
      packages.concat(layers)

      standalone = resolve_standalone(repo_path, base_packages, matched_dirs, dirs)
      packages.concat(standalone)
    end

    # Repos without base packages stow all top-level directories
    def resolve_all_packages(repo_path)
      top_level_dirs(repo_path)
        .sort
        .map { |d| [repo_path, d] }
    end

    def resolve_layers(repo_path, base_packages, dirs)
      os_packages = []
      distro_packages = []
      distro_profile_packages = []
      group_packages = []
      matched_dirs = Set.new(base_packages)

      dirs.each do |dir|
        next if base_packages.include?(dir)

        case dir
        when suffix("-#{@detection.os}")
          os_packages << [repo_path, dir]
          matched_dirs << dir
        when *@detection.distros.map { |d| suffix("-#{d}") }
          distro_packages << [repo_path, dir]
          matched_dirs << dir
        when *@detection.distros.map { |d| suffix("-#{d}-#{@detection.profile}") }
          distro_profile_packages << [repo_path, dir]
          matched_dirs << dir
        when *@detection.groups.map { |g| suffix("-#{g}") }
          group_packages << [repo_path, dir]
          matched_dirs << dir
        end
      end

      layers = os_packages + distro_packages + distro_profile_packages + group_packages
      [layers, matched_dirs]
    end

    def resolve_standalone(repo_path, base_packages, matched_dirs, dirs)
      dirs
        .reject { |d| matched_dirs.include?(d) || layer_variant?(d, base_packages) }
        .sort
        .map { |d| [repo_path, d] }
    end

    def top_level_dirs(repo_path)
      Dir.children(repo_path)
        .select { |d| File.directory?(File.join(repo_path, d)) }
        .reject { |d| d.start_with?(".") }
    end

    # Returns true if dir looks like a layer variant of any base package.
    # By convention, any <base>-<suffix> directory is a layer variant
    # for another OS, distro, profile, or group.
    def layer_variant?(dir, base_packages)
      base_packages.any? { |pkg| dir.start_with?("#{pkg}-") }
    end

    def suffix(s)
      ->(dir) { dir.end_with?(s) }
    end
  end
end
