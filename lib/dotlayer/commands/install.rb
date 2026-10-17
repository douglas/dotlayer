module Dotlayer
  module Commands
    class Install
      include Output

      def initialize(config:, detector: nil, dry_run: false, verbose: false)
        @config = config
        @detector = detector || Detector.new(config: @config)
        @dry_run = dry_run
        @verbose = verbose
        @system_failures = 0
      end

      def run
        detection = @detector.detect
        resolver = Resolver.new(config: @config, detection: detection)
        packages = resolver.resolve
        stow = Stow.new(target: @config.target, dry_run: @dry_run, verbose: @verbose)

        heading "Installing dotfiles (#{detection.os}/#{detection.profile}/#{detection.machine})"
        puts

        failures = packages.count do |repo_path, package|
          !restow_package(stow, repo_path, package)
        end

        abort_failed_packages(failures) if failures.positive?

        install_system_files if detection.os == "linux"

        puts
        abort "Error: #{@system_failures} system file(s) or hook(s) failed." if @system_failures.positive?
        puts "Done! #{packages.size} package(s) stowed."
      end

      private

      def abort_failed_packages(failures)
        puts
        abort "Error: #{failures} package(s) failed to stow."
      end

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

          # install -D creates missing parent dirs (e.g. /etc/systemd/system-sleep).
          if system("sudo", "install", "-D", "-m", mode || "0644", source, dest)
            ok
          else
            @system_failures += 1
            error("failed")
          end
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
            next ok if system(cmd)

            @system_failures += 1
            error("failed")
          end
        end
      end
    end
  end
end
