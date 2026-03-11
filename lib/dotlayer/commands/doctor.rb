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
        print "  Checking for broken symlinks in #{@config.target}... "
        broken = find_broken_symlinks(@config.target)
        if broken.empty?
          ok "none"
        else
          warning "#{broken.size} found"
          broken.each do |link|
            target = File.readlink(link) rescue "(deleted)"
            @issues << "Broken symlink: #{link} -> #{target}"
          end
        end
      end

      def find_broken_symlinks(target)
        broken = []
        scan_dirs = @packages.flat_map { |repo_path, package|
          pkg_dir = File.join(repo_path, package)
          next [] unless Dir.exist?(pkg_dir)

          Dir.children(pkg_dir).map { |child| File.join(target, child) }
        }.uniq

        scan_dirs.each do |dir|
          next unless File.exist?(dir) || File.symlink?(dir)

          if File.symlink?(dir) && !File.exist?(dir)
            broken << dir
            next
          end

          next unless File.directory?(dir)

          Dir.glob(File.join(dir, "**", "*"), File::FNM_DOTMATCH).each do |path|
            broken << path if File.symlink?(path) && !File.exist?(path)
          end
        end

        broken
      end
    end
  end
end
