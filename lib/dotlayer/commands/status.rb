module Dotlayer
  module Commands
    class Status
      include Output

      def initialize(config:, detector: nil)
        @config = config
        @detector = detector || Detector.new(config: @config)
      end

      def run
        detection = @detector.detect
        resolver = Resolver.new(config: @config, detection: detection)
        packages = resolver.resolve

        print_detection(detection)
        print_packages(packages)
      end

      private

      def print_detection(detection)
        heading "System Detection"
        puts "  Config:     #{config_label}"
        puts "  OS:         #{detection.os}"
        puts "  Profile:    #{detection.profile}"
        puts "  Machine:    #{detection.machine}"
        print_model(detection.model)
        puts "  Distros:    #{detection.distros.empty? ? "(none)" : detection.distros.join(", ")}"
        puts "  Groups:     #{detection.groups.empty? ? "(none)" : detection.groups.join(", ")}"
        puts
      end

      def config_label
        return "(none found, using defaults)" unless @config.path

        "#{tilde(@config.path)} (#{@config.source})"
      end

      # Every source a `model:` rule can match, so users can write rules.
      def print_model(model)
        if model.empty?
          puts "  Model:      (none read)"
        else
          model.each { |source, text| puts "  Model:      #{text}  (#{source})" }
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
