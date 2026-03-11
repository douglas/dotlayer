require "fileutils"

module Dotlayer
  module Commands
    class Adopt
      include Output

      def initialize(config:, paths:, package:, private_repo: false, dry_run: false, verbose: false)
        @config = config
        @paths = paths
        @package = package
        @private_repo = private_repo
        @dry_run = dry_run
        @verbose = verbose
        @target = File.expand_path(@config.target)
      end

      def run
        repo_path = find_repo
        unless repo_path
          abort "Error: package '#{@package}' not found in any repo"
        end

        stow = Stow.new(target: @target, dry_run: @dry_run, verbose: @verbose)

        @paths.each do |path|
          adopt_path(File.expand_path(path), repo_path)
        end

        restow_package(stow, repo_path, @package, verb: "Restowing")
      end

      private

      def find_repo
        if @private_repo
          repo = @config.repos.find(&:private)
          return repo.path if repo
          abort "Error: no private repo found in config (add private: true to a repo)"
        end

        @config.repos.each do |repo|
          next unless Dir.exist?(repo.path)

          pkg_dir = File.join(repo.path, @package)
          return repo.path if Dir.exist?(pkg_dir)
        end

        # Package doesn't exist yet — use first repo
        @config.repos.first&.path
      end

      def adopt_path(source, repo_path)
        unless File.exist?(source)
          error "  Skipping #{source}: does not exist"
          return
        end

        relative = relative_to_target(source)
        unless relative
          error "  Skipping #{source}: not under target #{@target}"
          return
        end

        dest = File.join(repo_path, @package, relative)

        if File.exist?(dest)
          warning "  Skipping #{relative}: already exists in #{@package}"
          return
        end

        puts "  Moving #{green(relative)} → #{@package}/"

        return if @dry_run

        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.mv(source, dest)
      end

      def relative_to_target(path)
        path = File.expand_path(path)
        return nil unless path.start_with?("#{@target}/")

        path.delete_prefix("#{@target}/")
      end
    end
  end
end
