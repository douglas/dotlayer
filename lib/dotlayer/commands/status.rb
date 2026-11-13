require "json"

module Dotlayer
  module Commands
    class Status
      include Output

      def initialize(config:, detector: nil, json: false)
        @config = config
        @detector = detector || Detector.new(config: @config)
        @json = json
      end

      def run
        detection = @detector.detect
        resolver = Resolver.new(config: @config, detection: detection)
        packages = resolver.resolve

        return puts(JSON.pretty_generate(report(detection, packages))) if @json

        print_detection(detection)
        print_packages(packages)
      end

      private

      # The documented --json shape.
      def report(detection, packages)
        {
          config: {path: @config.path, source: @config.source},
          os: detection.os,
          profile: detection.profile,
          machine: detection.machine,
          distros: detection.distros,
          groups: detection.groups,
          model: detection.model,
          packages: packages.map do |repo_path, package|
            {repo: repo_path, name: package, target: @config.target_for(repo_path, package)}
          end
        }
      end

      def print_detection(detection)
        heading "System Detection"
        puts "  #{muted("Config:")}    #{config_label}"
        puts "  #{muted("OS:")}        #{detection.os}"
        puts "  #{muted("Profile:")}   #{detection.profile}"
        puts "  #{muted("Machine:")}   #{detection.machine}"
        print_model(detection.model)
        puts "  #{muted("Distros:")}   #{detection.distros.empty? ? "(none)" : detection.distros.join(", ")}"
        puts "  #{muted("Groups:")}    #{detection.groups.empty? ? "(none)" : detection.groups.join(", ")}"
        puts
      end

      def config_label
        return "(none found, using defaults)" unless @config.path

        "#{tilde(@config.path)} (#{@config.source})"
      end

      # Every source a `model:` rule can match, so users can write rules.
      def print_model(model)
        if model.empty?
          puts "  #{muted("Model:")}     (none read)"
        else
          model.each { |source, text| puts "  #{muted("Model:")}     #{text}  (#{source})" }
        end
      end

      def tilde(path)
        path.start_with?("#{Dir.home}/") ? path.sub(Dir.home, "~") : path
      end

      def print_packages(packages)
        heading "Packages to stow"

        packages.each do |repo_path, package|
          repo_name = File.basename(repo_path)
          target = @config.target_for(repo_path, package)
          suffix = (target == @config.target) ? "" : " -> #{tilde(target)}"
          puts "  #{repo_name}/#{green(package)}#{suffix}"
        end

        puts
        puts "  #{packages.size} package(s) total"
      end
    end
  end
end
