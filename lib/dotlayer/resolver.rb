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

        packages.concat(resolve_repo(repo_path))
      end

      packages
    end

    private

    def resolve_repo(repo_path)
      has_base_packages = @config.packages.any? { |pkg| Dir.exist?(File.join(repo_path, pkg)) }

      if has_base_packages
        resolve_layered_repo(repo_path)
      else
        resolve_all_packages(repo_path)
      end
    end

    # Repos with base packages use layered convention matching
    def resolve_layered_repo(repo_path)
      packages = []

      @config.packages.each do |pkg|
        packages << [repo_path, pkg] if Dir.exist?(File.join(repo_path, pkg))
      end

      packages.concat(resolve_layers(repo_path))
    end

    # Repos without base packages stow all top-level directories
    def resolve_all_packages(repo_path)
      Dir.children(repo_path)
        .select { |d| File.directory?(File.join(repo_path, d)) }
        .reject { |d| d.start_with?(".") }
        .sort
        .map { |d| [repo_path, d] }
    end

    def resolve_layers(repo_path)
      dirs = Dir.children(repo_path)
        .select { |d| File.directory?(File.join(repo_path, d)) }
        .reject { |d| d.start_with?(".") }

      base_names = @config.packages

      os_packages = []
      distro_packages = []
      distro_profile_packages = []

      dirs.each do |dir|
        next if base_names.include?(dir)

        case dir
        when suffix("-#{@detection.os}")
          os_packages << [repo_path, dir]
        when *@detection.distros.map { |d| suffix("-#{d}") }
          distro_packages << [repo_path, dir]
        when *@detection.distros.map { |d| suffix("-#{d}-#{@detection.profile}") }
          distro_profile_packages << [repo_path, dir]
        end
      end

      os_packages + distro_packages + distro_profile_packages
    end

    def suffix(s)
      ->(dir) { dir.end_with?(s) }
    end
  end
end
