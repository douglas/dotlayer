module Dotlayer
  module Commands
    # Read-only preview of what `install` would change. Runs stow in
    # simulate mode (-n -v) and compares system files byte-for-byte.
    # #run returns true when nothing is pending, false otherwise.
    class Diff
      include Output

      LINK_LINE = /\A(LINK|UNLINK): (.+?)(?: => .*?)?( \(reverts previous action\))?\z/
      CONFLICT_LINE = /\A\s+\* (.+)\z/

      def initialize(config:, detector: nil)
        @config = config
        @detector = detector || Detector.new(config: @config)
        @pending = 0
      end

      def run
        detection = @detector.detect
        packages = Resolver.new(config: @config, detection: detection).resolve
        stow = Stow.new(target: @config.target, dry_run: true, verbose: true, quiet: true)

        heading "Diff (#{detection.os}/#{detection.profile}/#{detection.machine})"
        puts

        packages.each { |repo_path, package| diff_package(stow, repo_path, package) }
        diff_system_files if detection.os == "linux"

        puts
        warning "  Note: #{Stow::GLOBAL_IGNORE_NOTE}" if Stow.pending_global_ignore(packages).any?
        if @pending.zero?
          ok "No changes pending."
        else
          warning "#{@pending} change(s) pending."
        end
        @pending.zero?
      end

      private

      def diff_package(stow, repo_path, package)
        target = @config.target_for(repo_path, package)
        return diff_missing_target(repo_path, package, target) unless Dir.exist?(target)

        success = stow.restow(repo_path, package, target:)
        plan = parse_plan(stow.last_output.to_s)
        problems = success ? [] : plan[:conflicts]
        problems = [stow.last_error] if !success && problems.empty?
        return if plan[:links].empty? && plan[:unlinks].empty? && problems.empty?

        puts "  #{green(package)} (#{File.basename(repo_path)})"
        plan[:links].each { |path| puts "    #{green("LINK")}    #{path}" }
        plan[:unlinks].each { |path| puts "    #{yellow("UNLINK")}  #{path}" }
        problems.each { |problem| puts "    #{red("CONFLICT")} #{problem}" }
        @pending += plan[:links].size + plan[:unlinks].size + problems.size
      end

      # install creates a missing target dir, then links everything.
      def diff_missing_target(repo_path, package, target)
        puts "  #{green(package)} (#{File.basename(repo_path)})"
        puts "    #{green("LINK")}    #{package} files into new target #{target}"
        @pending += 1
      end

      # Restow shows UNLINK then LINK for links that already exist; stow marks
      # the second as "(reverts previous action)", so both cancel out.
      def parse_plan(output)
        links = []
        unlinks = []
        conflicts = []

        output.each_line(chomp: true) do |line|
          if (match = LINK_LINE.match(line))
            kind, path, reverts = match.captures
            if reverts
              (kind == "LINK") ? unlinks.delete(path) : links.delete(path)
            else
              ((kind == "LINK") ? links : unlinks) << path
            end
          elsif (match = CONFLICT_LINE.match(line))
            conflicts << match[1]
          end
        end

        {links:, unlinks:, conflicts: conflicts.uniq}
      end

      def diff_system_files
        entries = @config.system_files
        first_repo = @config.repos.first
        return if entries.empty? || first_repo.nil?

        changed = SystemFiles.pending(entries, first_repo)
        return if changed.empty?

        puts "  #{green("system files")}"
        changed.each { |change| puts "    #{yellow("CHANGE")}  #{change.dest} (#{change.reason})" }
        @pending += changed.size
      end
    end
  end
end
