require "open3"

module Dotlayer
  Detection = Data.define(:os, :profile, :machine, :distros, :groups)

  class Detector
    def initialize(config: Config.new)
      @config = config
    end

    def detect
      Detection.new(
        os: detect_os,
        profile: detect_profile,
        machine: detect_machine,
        distros: detect_distros,
        groups: detect_groups
      )
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
        output, status = Open3.capture2("sh", "-c", @config.profile_detect, err: File::NULL)
        return output.strip if status.success? && !output.strip.empty?
      end

      "desktop"
    end

    def detect_machine
      from_env = ENV[@config.machine_env]
      return normalize_tag(from_env) if from_env && !from_env.empty?

      detected = @config.machines.find do |name, entry|
        next false if name == "env"

        command_detected?(entry)
      end
      return normalize_tag(detected.first) if detected

      output, status = Open3.capture2("hostname", "-s", err: File::NULL)
      return normalize_tag(output) if status.success? && !output.strip.empty?

      "unknown"
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

    def normalize_tag(value)
      value.to_s.strip.downcase.gsub(/[^a-z0-9_-]+/, "-").gsub(/\A-+|-+\z/, "")
    end
  end
end
