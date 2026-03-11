module Dotlayer
  module Commands
    class Install
      include Output

      def initialize(config:, detector: nil, dry_run: false, verbose: false)
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
          restow_package(stow, repo_path, package)
        end

        install_system_files if detection.os == "linux"

        puts
        puts "Done! #{packages.size} package(s) stowed."
      end

      private

      def install_system_files
        return if @config.system_files.empty?

        first_repo = @config.repos.first
        unless first_repo
          warning "  Skipping system files: no repos configured"
          return
        end

        puts
        heading "System files"

        unless @dry_run
          return unless confirm("The following files will be installed with sudo:",
            @config.system_files.map { |e| e["dest"] })
        end

        @config.system_files.each do |entry|
          source = File.expand_path(entry["source"], first_repo.path)
          dest = entry["dest"]
          mode = entry["mode"]

          print "  #{dest}... "

          if @dry_run
            warning("dry-run")
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

      def confirm(message, items)
        puts "  #{message}"
        items.each { |item| puts "    #{item}" }
        print "  Continue? [y/N] "
        if $stdin.gets&.strip&.downcase == "y"
          true
        else
          warning("  Skipped.")
          false
        end
      end

      def run_hooks(name)
        commands = Array(@config.hooks[name])
        return if commands.empty?

        puts
        heading "Running #{name} hooks"

        unless @dry_run
          return unless confirm("The following commands will be executed:", commands)
        end

        commands.each do |cmd|
          print "  #{cmd}... "
          if @dry_run
            warning("dry-run")
          else
            system(cmd) ? ok : error("failed")
          end
        end
      end
    end
  end
end
