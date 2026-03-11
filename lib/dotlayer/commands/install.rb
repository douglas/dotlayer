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

        first_repo = @config.repos.first
        unless first_repo
          warn_text "  Skipping system files: no repos configured"
          return
        end

        puts
        heading "System files"

        unless @dry_run
          puts "  The following files will be installed with sudo:"
          @config.system_files.each { |e| puts "    #{e["dest"]}" }
          print "  Continue? [y/N] "
          unless $stdin.gets&.strip&.downcase == "y"
            warn_text("  Skipped.")
            return
          end
        end

        @config.system_files.each do |entry|
          source = File.expand_path(entry["source"], first_repo["path"])
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
        commands = Array(@config.hooks[name])
        return if commands.empty?

        puts
        heading "Running #{name} hooks"

        unless @dry_run
          puts "  The following commands will be executed:"
          commands.each { |cmd| puts "    #{cmd}" }
          print "  Continue? [y/N] "
          unless $stdin.gets&.strip&.downcase == "y"
            warn_text("  Skipped.")
            return
          end
        end

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
