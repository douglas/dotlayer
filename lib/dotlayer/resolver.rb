module Dotlayer
  class Resolver
    def initialize(config:, detection:)
      @config = config
      @detection = detection
    end

    def resolve
      packages = []

      @config.repos.each do |repo|
        next unless Dir.exist?(repo.path)

        base_packages = repo.packages || @config.packages
        packages.concat(resolve_repo(repo, base_packages))
      end

      packages
    end

    private

    def resolve_repo(repo, base_packages)
      # Repos with explicit packages always use layered resolution,
      # even if the directories don't exist yet
      if repo.packages || base_packages.any? { |pkg| Dir.exist?(File.join(repo.path, pkg)) }
        resolve_layered_repo(repo, base_packages)
      else
        resolve_all_packages(repo.path)
      end
    end

    # Repos with base packages use layered convention matching
    # plus standalone directories that don't match any layer pattern
    def resolve_layered_repo(repo, base_packages)
      repo_path = repo.path
      packages = []

      base_packages.each do |pkg|
        packages << [repo_path, pkg] if Dir.exist?(File.join(repo_path, pkg))
      end

      dirs = top_level_dirs(repo_path)
      layers, matched_dirs = resolve_layers(repo, base_packages, dirs)
      packages.concat(layers)

      standalone = resolve_standalone(repo, base_packages, matched_dirs, dirs)
      packages.concat(standalone)
    end

    # Repos without base packages stow all top-level directories
    def resolve_all_packages(repo_path)
      top_level_dirs(repo_path)
        .sort
        .map { |d| [repo_path, d] }
    end

    def resolve_layers(repo, base_packages, dirs)
      repo_path = repo.path
      os_packages = []
      distro_packages = []
      distro_profile_packages = []
      machine_packages = []
      os_machine_packages = []
      distro_machine_packages = []
      distro_profile_machine_packages = []
      group_packages = []
      matched_dirs = base_packages.dup

      dirs.each do |dir|
        next if base_packages.include?(dir)

        case dir
        when *@detection.distros.map { |d| suffix("-#{d}-#{@detection.profile}-#{@detection.machine}") }
          distro_profile_machine_packages << [repo_path, dir]
          matched_dirs << dir
        when *@detection.distros.map { |d| suffix("-#{d}-#{@detection.machine}") }
          distro_machine_packages << [repo_path, dir]
          matched_dirs << dir
        when suffix("-#{@detection.os}-#{@detection.machine}")
          os_machine_packages << [repo_path, dir]
          matched_dirs << dir
        when suffix("-#{@detection.machine}")
          machine_packages << [repo_path, dir]
          matched_dirs << dir
        when *@detection.distros.map { |d| suffix("-#{d}-#{@detection.profile}") }
          distro_profile_packages << [repo_path, dir]
          matched_dirs << dir
        when *@detection.distros.map { |d| suffix("-#{d}") }
          distro_packages << [repo_path, dir]
          matched_dirs << dir
        when suffix("-#{@detection.os}")
          os_packages << [repo_path, dir]
          matched_dirs << dir
        when *@detection.groups.map { |g| suffix("-#{g}") }
          group_packages << [repo_path, dir]
          matched_dirs << dir
        end
      end

      group_packages.concat(resolve_group_packages(repo, matched_dirs))
      layers = os_packages + distro_packages + distro_profile_packages +
        machine_packages + os_machine_packages + distro_machine_packages +
        distro_profile_machine_packages + group_packages
      [layers, matched_dirs]
    end

    def resolve_group_packages(repo, matched_dirs)
      @detection.groups.flat_map do |group|
        Array(repo.group_packages[group]).filter_map do |package|
          next if matched_dirs.include?(package)
          next unless Dir.exist?(File.join(repo.path, package))

          matched_dirs << package
          [repo.path, package]
        end
      end
    end

    def resolve_standalone(repo, base_packages, matched_dirs, dirs)
      if repo.standalone_packages
        return repo.standalone_packages.filter_map do |package|
          next if matched_dirs.include?(package)
          next unless Dir.exist?(File.join(repo.path, package))

          [repo.path, package]
        end
      end

      dirs
        .reject { |d| matched_dirs.include?(d) || layer_variant?(d, base_packages) }
        .sort
        .map { |d| [repo.path, d] }
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
