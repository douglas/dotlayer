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
        if @pending.zero?
          ok "No changes pending."
        else
          warning "#{@pending} change(s) pending."
        end
        @pending.zero?
      end

      private

      def diff_package(stow, repo_path, package)
        success = stow.restow(repo_path, package)
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

        {links:, unlinks:, conflicts:}
      end

      def diff_system_files
        entries = @config.system_files
        first_repo = @config.repos.first
        return if entries.empty? || first_repo.nil?

        changed = entries.filter_map { |entry| system_file_change(entry, first_repo) }
        return if changed.empty?

        puts "  #{green("system files")}"
        changed.each { |dest, reason| puts "    #{yellow("CHANGE")}  #{dest} (#{reason})" }
        @pending += changed.size
      end

      def system_file_change(entry, repo)
        source = File.expand_path(entry["source"], repo.path)
        dest = entry["dest"]
        mode = (entry["mode"] || "0644").to_s.to_i(8)

        return [dest, "source missing: #{source}"] unless File.file?(source)
        return [dest, "missing"] unless File.exist?(dest)

        reasons = []
        reasons << "content differs" unless File.binread(source) == File.binread(dest)
        actual_mode = File.stat(dest).mode & 0o7777
        reasons << format("mode %04o, want %04o", actual_mode, mode) unless actual_mode == mode
        [dest, reasons.join(", ")] unless reasons.empty?
      rescue Errno::EACCES
        [dest, "unreadable, cannot compare"]
      end
    end
  end
end
