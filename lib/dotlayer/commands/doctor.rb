module Dotlayer
  module Commands
    class Doctor
      include Output

      def initialize(config:, detector: nil)
        @config = config
        @detector = detector || Detector.new(config: @config)
        @issues = []
      end

      def run
        detection = @detector.detect
        resolver = Resolver.new(config: @config, detection: detection)
        @packages = resolver.resolve

        heading "Dotlayer Doctor"
        puts

        check_stow_installed
        check_repos_exist
        check_packages_exist(@packages)
        check_broken_symlinks

        puts
        if @issues.empty?
          ok "No issues found."
        else
          error "#{@issues.size} issue(s) found:"
          @issues.each { |issue| puts "  - #{issue}" }
        end
      end

      private

      def check_stow_installed
        print "  Checking stow... "
        if system("which", "stow", out: File::NULL, err: File::NULL)
          ok "installed"
        else
          error "missing"
          @issues << "GNU Stow is not installed"
        end
      end

      def check_repos_exist
        @config.repos.each do |repo|
          print "  Checking repo #{repo.path}... "
          if Dir.exist?(repo.path)
            ok "exists"
          else
            error "missing"
            @issues << "Repo not found: #{repo.path}"
          end
        end
      end

      def check_packages_exist(packages)
        packages.each do |repo_path, package|
          pkg_path = File.join(repo_path, package)
          unless Dir.exist?(pkg_path)
            @issues << "Package directory missing: #{pkg_path}"
          end
        end
      end

      def check_broken_symlinks
        print "  Checking for broken symlinks in managed config paths... "
        broken = find_broken_symlinks(@config.target)
        if broken.empty?
          ok "none"
        else
          warning "#{broken.size} found"
          broken.each do |link|
            target = begin
              File.readlink(link)
            rescue
              "(deleted)"
            end
            @issues << "Broken symlink: #{link} -> #{target}"
          end
        end
      end

      def find_broken_symlinks(target)
        broken = []
        managed_roots = [".config", ".local"]
        scan_paths = @packages.flat_map { |repo_path, package|
          pkg_dir = File.join(repo_path, package)
          next [] unless Dir.exist?(pkg_dir)

          managed_roots.flat_map do |root_name|
            root_path = File.join(pkg_dir, root_name)
            next [] unless File.exist?(root_path) || File.symlink?(root_path)

            managed_paths = [root_path]
            if File.directory?(root_path)
              managed_paths.concat(Dir.glob(File.join(root_path, "**", "*"), File::FNM_DOTMATCH))
            end

            managed_paths
              .reject { |path| [".", ".."].include?(File.basename(path)) }
              .map { |path| File.join(target, path.delete_prefix("#{pkg_dir}/")) }
          end
        }.uniq

        scan_paths.each do |path|
          broken << path if File.symlink?(path) && !File.exist?(path)
        end

        broken
      end
    end
  end
end
