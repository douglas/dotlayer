require "open3"

module Dotlayer
  module Commands
    class Update
      include Output

      def initialize(config:, detector: nil, dry_run: false, verbose: false)
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
        heading "Pulling repos"

        @config.repos.each do |repo|
          next unless Dir.exist?(File.join(repo.path, ".git"))

          print "  #{File.basename(repo.path)}... "

          if @dry_run
            warning("dry-run")
            next
          end

          output, status = Open3.capture2e("git", "-C", repo.path, "pull", "--rebase")
          if status.success?
            ok
          else
            error("failed")
            puts "    #{output.strip}"
          end
        end

        puts
      end

      def restow_packages
        detection = @detector.detect
        resolver = Resolver.new(config: @config, detection: detection)
        packages = resolver.resolve
        stow = Stow.new(target: @config.target, dry_run: @dry_run, verbose: @verbose)

        heading "Re-stowing packages"

        packages.each do |repo_path, package|
          restow_package(stow, repo_path, package, verb: "Restowing")
        end

        puts
        puts "Done! #{packages.size} package(s) restowed."
      end
    end
  end
end
