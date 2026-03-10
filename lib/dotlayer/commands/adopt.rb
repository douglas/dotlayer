require "fileutils"

module Dotlayer
  module Commands
    class Adopt
      def initialize(config:, paths:, package:, dry_run: false, verbose: false)
        @config = config
        @paths = paths
        @package = package
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

        print "  Restowing \e[32m#{@package}\e[0m... "
        if @dry_run
          puts "\e[33mdry-run\e[0m"
        elsif stow.restow(repo_path, @package)
          puts "\e[32mok\e[0m"
        else
          puts "\e[31mfailed\e[0m"
        end
      end

      private

      def find_repo
        @config.repos.each do |repo|
          repo_path = repo["path"]
          next unless repo_path && Dir.exist?(repo_path)

          pkg_dir = File.join(repo_path, @package)
          return repo_path if Dir.exist?(pkg_dir)
        end

        # Package doesn't exist yet — use first repo
        @config.repos.first&.dig("path")
      end

      def adopt_path(source, repo_path)
        unless File.exist?(source)
          warn "  \e[31mSkipping #{source}: does not exist\e[0m"
          return
        end

        relative = relative_to_target(source)
        unless relative
          abort "Error: #{source} is not under target #{@target}"
        end

        dest = File.join(repo_path, @package, relative)

        if File.exist?(dest)
          warn "  \e[33mSkipping #{relative}: already exists in #{@package}\e[0m"
          return
        end

        puts "  Moving \e[32m#{relative}\e[0m → #{@package}/"

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
