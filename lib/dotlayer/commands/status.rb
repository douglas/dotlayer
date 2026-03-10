module Dotlayer
  module Commands
    class Status
      def initialize(config: Config.new, detector: nil)
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
        puts "\e[1mSystem Detection\e[0m"
        puts "  OS:         #{detection.os}"
        puts "  Profile:    #{detection.profile}"
        puts "  Distros:    #{detection.distros.empty? ? "(none)" : detection.distros.join(", ")}"
        puts "  Groups:     #{detection.groups.empty? ? "(none)" : detection.groups.join(", ")}"
        puts
      end

      def print_packages(packages)
        puts "\e[1mPackages to stow\e[0m"

        packages.each do |repo_path, package|
          repo_name = File.basename(repo_path)
          puts "  #{repo_name}/\e[32m#{package}\e[0m"
        end

        puts
        puts "  #{packages.size} package(s) total"
      end
    end
  end
end
