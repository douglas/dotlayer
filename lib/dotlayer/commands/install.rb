module Dotlayer
  module Commands
    class Install
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

        puts "\e[1mInstalling dotfiles\e[0m (#{detection.os}/#{detection.profile})"
        puts

        packages.each do |repo_path, package|
          print "  Stowing \e[32m#{package}\e[0m... "
          if stow.stow(repo_path, package)
            puts "\e[32mok\e[0m"
          else
            puts "\e[31mfailed\e[0m"
          end
        end

        install_system_files if detection.os == "linux"

        puts
        puts "Done! #{packages.size} package(s) stowed."
      end

      private

      def install_system_files
        return if @config.system_files.empty?

        puts
        puts "\e[1mSystem files\e[0m"

        @config.system_files.each do |entry|
          source = File.expand_path(entry["source"], @config.repos.first["path"])
          dest = entry["dest"]
          mode = entry["mode"]

          print "  #{dest}... "

          if @dry_run
            puts "\e[33mdry-run\e[0m"
            next
          end

          system("sudo", "cp", source, dest)
          system("sudo", "chmod", mode, dest) if mode
          puts "\e[32mok\e[0m"
        end

        run_hooks("after_system_files")
      end

      def run_hooks(name)
        commands = @config.hooks[name]
        return unless commands

        puts
        puts "\e[1mRunning #{name} hooks\e[0m"

        commands.each do |cmd|
          print "  #{cmd}... "
          if @dry_run
            puts "\e[33mdry-run\e[0m"
          else
            system(cmd) ? puts("\e[32mok\e[0m") : puts("\e[31mfailed\e[0m")
          end
        end
      end
    end
  end
end
