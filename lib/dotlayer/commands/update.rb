module Dotlayer
  module Commands
    class Update
      def initialize(config: Config.new, detector: nil, dry_run: false, verbose: false)
        @config = config
        @detector = detector || Detector.new(config: @config)
        @dry_run = dry_run
        @verbose = verbose
      end

      def run
        pull_repos
        restow_packages
      end

      private

      def pull_repos
        puts "\e[1mPulling repos\e[0m"

        @config.repos.each do |repo|
          path = repo["path"]
          next unless Dir.exist?(File.join(path, ".git"))

          print "  #{File.basename(path)}... "

          if @dry_run
            puts "\e[33mdry-run\e[0m"
            next
          end

          output, status = Open3.capture2e("git", "-C", path, "pull", "--rebase")
          if status.success?
            puts "\e[32mok\e[0m"
          else
            puts "\e[31mfailed\e[0m"
            warn "    #{output.strip}"
          end
        end

        puts
      end

      def restow_packages
        detection = @detector.detect
        resolver = Resolver.new(config: @config, detection: detection)
        packages = resolver.resolve
        stow = Stow.new(target: @config.target, dry_run: @dry_run, verbose: @verbose)

        puts "\e[1mRe-stowing packages\e[0m"

        packages.each do |repo_path, package|
          print "  Restowing \e[32m#{package}\e[0m... "
          if stow.restow(repo_path, package)
            puts "\e[32mok\e[0m"
          else
            puts "\e[31mfailed\e[0m"
          end
        end

        puts
        puts "Done! #{packages.size} package(s) restowed."
      end
    end
  end
end
