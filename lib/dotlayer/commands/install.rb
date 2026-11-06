module Dotlayer
  module Commands
    class Install
      include Output

      def initialize(config:, detector: nil, dry_run: false, verbose: false, yes: false, backup: false)
        @config = config
        @detector = detector || Detector.new(config: @config)
        @dry_run = dry_run
        @verbose = verbose
        @yes = yes
        @backup = backup
        @system_failures = 0
      end

      def run
        detection = @detector.detect
        resolver = Resolver.new(config: @config, detection: detection)
        packages = resolver.resolve
        stow = Stow.new(target: @config.target, dry_run: @dry_run, verbose: @verbose)

        heading "Installing dotfiles (#{detection.os}/#{detection.profile}/#{detection.machine})"
        puts

        conflicts = ConflictBackup.new(config: @config, dry_run: @dry_run) if @backup
        failures = packages.count do |repo_path, package|
          !install_package(stow, conflicts, repo_path, package)
        end
        conflicts&.summary

        abort_failed_packages(failures) if failures.positive?

        install_system_files if detection.os == "linux"

        puts
        abort "Error: #{@system_failures} system file(s) or hook(s) failed." if @system_failures.positive?
        puts "Done! #{packages.size} package(s) stowed."
      end

      private

      def install_package(stow, conflicts, repo_path, package)
        target = @config.target_for(repo_path, package)
        resolved = conflicts&.resolve(repo_path, package, target:)
        if @dry_run && resolved&.positive?
          print "  Stowing #{green(package)}... "
          warning("dry-run, after the conflicts above are cleared")
          return true
        end

        success = restow_package(stow, repo_path, package, target:)
        @conflict_failed ||= !success && stow.last_error.to_s.each_line.any? { |l| Diff::CONFLICT_LINE.match?(l.chomp) }
        success
      end

      def abort_failed_packages(failures)
        puts
        if @conflict_failed && !@backup
          warning "Files in the way? Rerun with --backup to delete identical ones and move different ones to ~/dotfiles-conflicts-<time>/."
        end
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

        pending = SystemFiles.pending(@config.system_files, first_repo)
        if pending.empty?
          ok "  System files are up to date."
          return
        end

        return unless @dry_run || approve_system_files(pending)

        pending.each { |change| install_system_file(change) }

        run_hooks("after_system_files")
      end

      def approve_system_files(pending)
        if !@yes && !$stdin.tty?
          warning "  #{pending.size} system file(s) need installing. " \
            "Not a terminal, so nothing was asked: rerun with --yes to install them."
          return false
        end

        confirm("The following files will be installed with sudo:",
          pending.map { |change| "#{change.dest} (#{change.reason})" })
      end

      def install_system_file(change)
        print "  #{change.dest}... "

        return warning("dry-run") if @dry_run

        # install -D creates missing parent dirs (e.g. /etc/systemd/system-sleep).
        if File.file?(change.source) &&
            system("sudo", "install", "-D", "-m", change.mode, change.source, change.dest)
          ok
        else
          @system_failures += 1
          error("failed")
        end
      end

      def confirm(message, items)
        puts "  #{message}"
        items.each { |item| puts "    #{item}" }
        if @yes
          info "  Continue? yes (--yes)"
          return true
        end

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
