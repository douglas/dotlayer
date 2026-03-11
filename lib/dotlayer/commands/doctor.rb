module Dotlayer
  module Commands
    class Doctor
      include Output

      def initialize(config: Config.new, detector: nil)
        @config = config
        @detector = detector || Detector.new(config: @config)
        @issues = []
      end

      def run
        detection = @detector.detect
        resolver = Resolver.new(config: @config, detection: detection)
        packages = resolver.resolve

        heading "Dotlayer Doctor"
        puts

        check_stow_installed
        check_repos_exist
        check_packages_exist(packages)
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
          path = repo["path"]
          print "  Checking repo #{path}... "
          if Dir.exist?(path)
            ok "exists"
          else
            error "missing"
            @issues << "Repo not found: #{path}"
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
          warn_text "#{broken.size} found"
          broken.each do |link|
            @issues << "Broken symlink: #{link} -> #{File.readlink(link)}"
          end
        end
      end

      def find_broken_symlinks(dir)
        broken = []
        config_dir = File.join(dir, ".config")
        return broken unless Dir.exist?(config_dir)

        Dir.glob(File.join(config_dir, "**", "*"), File::FNM_DOTMATCH).each do |path|
          broken << path if File.symlink?(path) && !File.exist?(path)
        end

        broken
      end
    end
  end
end
