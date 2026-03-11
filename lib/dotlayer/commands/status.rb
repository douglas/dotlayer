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
        puts "  OS:         #{detection.os}"
        puts "  Profile:    #{detection.profile}"
        puts "  Distros:    #{detection.distros.empty? ? "(none)" : detection.distros.join(", ")}"
        puts "  Groups:     #{detection.groups.empty? ? "(none)" : detection.groups.join(", ")}"
        puts
      end

      def print_packages(packages)
        heading "Packages to stow"

        packages.each do |repo_path, package|
          repo_name = File.basename(repo_path)
          puts "  #{repo_name}/#{green(package)}"
        end

        puts
        puts "  #{packages.size} package(s) total"
      end
    end
  end
end
