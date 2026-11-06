require "fileutils"

module Dotlayer
  module Commands
    # `dotlayer machine add <name>`: writes a `model:` rule into the machines:
    # block of the config file (as text, so comments survive) and scaffolds the
    # machine's layer dir in the first repo, copied from another machine's layer.
    class MachineAdd
      include Output

      NAME = /\A[a-z0-9][a-z0-9-]*\z/
      PROFILES = %w[laptop desktop].freeze
      # Files that only fit the machine being copied from.
      SKIP_FILES = %w[.config/hypr/monitors.lua].freeze

      def initialize(config:, name:, detector: nil, match: nil, profile: nil, from: nil, distro: nil, dry_run: false)
        @config = config
        @detector = detector || Detector.new(config: @config)
        @name = name
        @match = match
        @profile = profile
        @from = from
        @distro = distro
        @dry_run = dry_run
      end

      # Adds the lines as the last entry of the machines: block, or a new
      # block at the end. Everything else in the file stays as it was.
      def self.insert_rule(text, entry_lines, path = "config")
        lines = text.lines
        start = lines.index { |l| l.start_with?("machines:") }
        unless start
          lines[-1] += "\n" if lines.any? && !lines.last.end_with?("\n")
          return (lines + ["\n", "machines:\n"] + entry_lines).join
        end

        unless lines[start].sub(/#.*/, "").strip == "machines:"
          abort "Error: machines: in #{path} is written inline; add the machine by hand"
        end

        stop = (start + 1...lines.size).find { |i| lines[i].match?(/\A\S/) } || lines.size
        stop -= 1 while stop > start + 1 && lines[stop - 1].strip.empty?
        lines[stop - 1] += "\n" unless lines[stop - 1].end_with?("\n")
        lines.insert(stop, *entry_lines)
        lines.join
      end

      def run
        abort "Error: machine name: lowercase letters, digits, dashes" unless @name&.match?(NAME)
        abort "Error: no config file to edit (pass -c PATH)" unless @config.path && File.exist?(@config.path)

        detection = @detector.detect
        match = resolve_match(detection)
        profile = resolve_profile(detection)
        distro = resolve_distro(detection)
        repo = first_repo
        base = base_package(repo)
        dest = File.join(repo.path, layer_name(base, distro, profile, @name))
        source = source_layer(repo, base, distro, profile)
        check_free(dest)

        summarize(match, profile, dest, source)
        return puts("Dry run: nothing written.") if @dry_run

        scaffold(source, dest)
        write_rule(match)
        puts
        puts "Done. Next: adjust the layer, review with git diff, commit, then run dotlayer install."
      end

      private

      def resolve_match(detection)
        match = @match || Model.best_guess(detection.model)
        abort "Error: could not read the model; pass --match" if match.nil? || match.empty?
        abort "Error: --match can't contain quotes or backslashes" if match.match?(/["'\\]/)
        match
      end

      def resolve_profile(detection)
        profile = @profile || detection.profile
        abort "Error: profile must be laptop or desktop" unless PROFILES.include?(profile)
        profile
      end

      # Layers are named like the resolver finds them: <base>-<distro>-<profile>-<machine>.
      def resolve_distro(detection)
        return @distro if @distro

        distros = detection.distros
        if distros.size > 1
          abort "Error: more than one distro detected (#{distros.join(", ")}); pass --distro"
        end
        distros.first
      end

      def first_repo
        repo = @config.repos.first
        abort "Error: no repo configured" unless repo && Dir.exist?(repo.path)
        repo
      end

      def base_package(repo)
        bases = repo.packages || @config.packages
        bases.include?("config") ? "config" : bases.first
      end

      def layer_name(base, distro, profile, machine)
        distro ? "#{base}-#{distro}-#{profile}-#{machine}" : "#{base}-#{machine}"
      end

      def source_layer(repo, base, distro, profile)
        return nil unless @from

        source = File.join(repo.path, layer_name(base, distro, profile, @from))
        abort "Error: no layer to copy: #{source}" unless Dir.exist?(source)
        source
      end

      def check_free(dest)
        if @config.machines.key?(@name) || File.readlines(@config.path).any? { |l| l.match?(/\A  #{Regexp.escape(@name)}:/) }
          abort "Error: #{@config.path} already has machine #{@name}"
        end
        abort "Error: layer already exists: #{dest}" if File.exist?(dest)
      end

      def summarize(match, profile, dest, source)
        puts "machine:  #{@name} (#{profile}), matched by model containing \"#{match}\""
        puts "layer:    #{dest}#{" (copied from #{File.basename(source)}, without monitors)" if source}"
        puts "rule:     #{rule_lines(match).map(&:strip).join(" ")}"
      end

      def scaffold(source, dest)
        FileUtils.mkdir_p(dest)
        return unless source

        Dir.glob("**/*", File::FNM_DOTMATCH, base: source).each do |rel|
          next if %w[. ..].include?(File.basename(rel)) || SKIP_FILES.include?(rel)

          from = File.join(source, rel)
          to = File.join(dest, rel)
          if File.symlink?(from)
            FileUtils.mkdir_p(File.dirname(to))
            File.symlink(File.readlink(from), to)
          elsif File.directory?(from)
            FileUtils.mkdir_p(to)
          else
            FileUtils.mkdir_p(File.dirname(to))
            FileUtils.cp(from, to, preserve: true)
          end
        end
      end

      def rule_lines(match)
        ["  #{@name}:\n", "    model: \"#{match}\"\n"]
      end

      def write_rule(match)
        File.write(@config.path, self.class.insert_rule(File.read(@config.path), rule_lines(match), @config.path))
      end
    end
  end
end
