module Dotlayer
  module Commands
    class Doctor
      def initialize(config: Config.new, detector: nil)
        @config = config
        @detector = detector || Detector.new(config: @config)
        @issues = []
      end

      def run
        detection = @detector.detect
        resolver = Resolver.new(config: @config, detection: detection)
        packages = resolver.resolve

        puts "\e[1mDotlayer Doctor\e[0m"
        puts

        check_stow_installed
        check_repos_exist
        check_packages_exist(packages)
        check_broken_symlinks
        check_missing_includes

        puts
        if @issues.empty?
          puts "\e[32mNo issues found.\e[0m"
        else
          puts "\e[31m#{@issues.size} issue(s) found:\e[0m"
          @issues.each { |issue| puts "  - #{issue}" }
        end
      end

      private

      def check_stow_installed
        print "  Checking stow... "
        if system("which", "stow", out: File::NULL, err: File::NULL)
          puts "\e[32minstalled\e[0m"
        else
          puts "\e[31mmissing\e[0m"
          @issues << "GNU Stow is not installed"
        end
      end

      def check_repos_exist
        @config.repos.each do |repo|
          path = repo["path"]
          print "  Checking repo #{path}... "
          if Dir.exist?(path)
            puts "\e[32mexists\e[0m"
          else
            puts "\e[31mmissing\e[0m"
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
          puts "\e[32mnone\e[0m"
        else
          puts "\e[33m#{broken.size} found\e[0m"
          broken.each do |link|
            @issues << "Broken symlink: #{link} -> #{File.readlink(link)}"
          end
        end
      end

      def check_missing_includes
        ghostty_config = File.join(@config.target, ".config", "ghostty", "config")
        return unless File.exist?(ghostty_config)

        print "  Checking Ghostty config-file includes... "

        File.readlines(ghostty_config).each do |line|
          next unless line =~ /\Aconfig-file\s*=\s*(\S+)/
          include_file = $1
          next if include_file.start_with?("?") # optional include

          include_path = File.join(File.dirname(ghostty_config), include_file)
          unless File.exist?(include_path)
            puts "\e[31mmissing\e[0m"
            @issues << "Ghostty config references missing include: #{include_path}"
            return
          end
        end

        puts "\e[32mok\e[0m"
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
