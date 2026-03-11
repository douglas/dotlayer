module Dotlayer
  module Commands
    class Install
      include Output

      def initialize(config: Config.new, detector: nil, dry_run: false, verbose: false)
        @config = config
        @detector = detector || Detector.new(config: @config)
        @dry_run = dry_run
        @verbose = verbose
      end

      def run
        detection = @detector.detect
        resolver = Resolver.new(config: @config, detection: detection)
        packages = resolver.resolve
        stow = Stow.new(target: @config.target, dry_run: @dry_run, verbose: @verbose)

        heading "Installing dotfiles (#{detection.os}/#{detection.profile})"
        puts

        packages.each do |repo_path, package|
          stow_package(stow, repo_path, package)
        end

        install_system_files if detection.os == "linux"

        puts
        puts "Done! #{packages.size} package(s) stowed."
      end

      private

      def install_system_files
        return if @config.system_files.empty?

        puts
        heading "System files"

        @config.system_files.each do |entry|
          source = File.expand_path(entry["source"], @config.repos.first["path"])
          dest = entry["dest"]
          mode = entry["mode"]

          print "  #{dest}... "

          if @dry_run
            warn_text("dry-run")
            next
          end

          unless system("sudo", "cp", source, dest)
            error("failed")
            next
          end

          if mode && !system("sudo", "chmod", mode, dest)
            error("chmod failed")
            next
          end

          ok
        end

        run_hooks("after_system_files")
      end

      def run_hooks(name)
        commands = @config.hooks[name]
        return unless commands

        puts
        heading "Running #{name} hooks"

        commands.each do |cmd|
          print "  #{cmd}... "
          if @dry_run
            warn_text("dry-run")
          else
            system(cmd) ? ok : error("failed")
          end
        end
      end
    end
  end
end
