require "open3"

module Dotlayer
  # model: {source path => text} read from the hardware, for display and rules.
  Detection = Data.define(:os, :profile, :machine, :distros, :groups, :model) do
    def initialize(model: {}, **rest)
      super
    end
  end

  # Chassis types from the SMBIOS spec that mean a portable or fixed machine.
  LAPTOP_CHASSIS = %w[8 9 10 14 30 31 32].freeze
  DESKTOP_CHASSIS = %w[3 4 5 6 7 15 16 35].freeze

  class Detector
    # root is the filesystem root the hardware files are read from.
    def initialize(config: Config.new, root: "/")
      @config = config
      @root = root
    end

    def detect
      @model = Model.read(root: @root)
      Detection.new(
        model: @model,
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

      if @config.profile_detect_configured?
        command = @config.profile_detect
        unless command.nil? || command.empty?
          output, status = Open3.capture2("sh", "-c", command, err: File::NULL)
          return output.strip if status.success? && !output.strip.empty?
        end
        return "desktop"
      end

      chassis_profile || "desktop"
    end

    # Without a profiles: detect command: DMI chassis_type, then hostnamectl.
    def chassis_profile
      type = File.read(File.join(@root, "sys/class/dmi/id/chassis_type")).strip
      return "laptop" if LAPTOP_CHASSIS.include?(type)
      return "desktop" if DESKTOP_CHASSIS.include?(type)

      hostnamectl_chassis
    rescue SystemCallError
      hostnamectl_chassis
    end

    def hostnamectl_chassis
      output, status = Open3.capture2("hostnamectl", "chassis", err: File::NULL)
      chassis = output.strip
      chassis if status.success? && !chassis.empty?
    rescue SystemCallError
      nil
    end

    def detect_machine
      from_env = ENV[@config.machine_env]
      return normalize_tag(from_env) if from_env && !from_env.empty?

      detected = @config.machines.find do |name, entry|
        next false if name == "env"

        machine_matches?(entry)
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

    # A machine rule is either a model: substring match or a detect: command.
    def machine_matches?(entry)
      return Model.match?(@model, entry["model"]) if entry.key?("model")

      command_detected?(entry)
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
