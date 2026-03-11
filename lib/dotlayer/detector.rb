require "open3"

module Dotlayer
  Detection = Data.define(:os, :profile, :distros, :groups)

  class Detector
    def initialize(config: Config.new)
      @config = config
    end

    def detect
      Detection.new(os: detect_os, profile: detect_profile, distros: detect_distros, groups: detect_groups)
    end

    private

    def detect_os
      case RbConfig::CONFIG["host_os"]
      when /darwin/ then "macos"
      when /linux/ then "linux"
      else "unknown"
      end
    end

    def detect_profile
      from_env = ENV[@config.profile_env]
      return from_env if from_env && !from_env.empty?

      if @config.profile_detect && !@config.profile_detect.empty?
        output, status = Open3.capture2(@config.profile_detect)
        return output.strip if status.success? && !output.strip.empty?
      end

      "desktop"
    end

    def detect_distros
      @config.distros.select { |_name, entry| command_detected?(entry) }.keys
    end

    def detect_groups
      @config.groups.select { |_name, entry| command_detected?(entry) }.keys
    end

    def command_detected?(entry)
      cmd = entry["detect"]
      return false unless cmd.is_a?(String) && !cmd.empty?

      _, status = Open3.capture2e("sh", "-c", cmd)
      status.success?
    end
  end
end
