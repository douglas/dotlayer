require "open3"
require "rbconfig"

module Dotlayer
  # The hardware model text a machine reports, read straight from the files
  # `machines:` rules with `model:` match against. root is injectable for tests.
  module Model
    SOURCES = %w[
      sys/class/dmi/id/product_name
      sys/class/dmi/id/product_version
      sys/class/dmi/id/board_name
      proc/device-tree/model
    ].freeze

    PLACEHOLDERS = ["Default string", "To Be Filled By O.E.M.", "System Product Name", "System Version"].freeze

    # {"/sys/class/dmi/id/product_name" => "ThinkPad ...", ...}: every
    # readable, non-empty source. NULs (device-tree) are stripped.
    def self.read(root: "/")
      found = SOURCES.each_with_object({}) do |relative, acc|
        text = File.read(File.join(root, relative)).delete("\0").strip
        acc["/#{relative}"] = text unless text.empty? || PLACEHOLDERS.include?(text)
      rescue SystemCallError
        next
      end

      if root == "/" && RbConfig::CONFIG["host_os"] =~ /darwin/
        hw = read_macos_model
        found["sysctl:hw.model"] = hw if hw && !hw.empty?
      end
      found
    end

    def self.read_macos_model
      output, status = Open3.capture2("sysctl", "-n", "hw.model", err: File::NULL)
      status.success? ? output.strip : nil
    rescue SystemCallError
      nil
    end

    def self.match?(sources, patterns)
      text = sources.values.join("\n")
      Array(patterns).any? { |pattern| text.include?(pattern) }
    end

    # The longest field is the model name: Lenovo puts it in product_version
    # (product_name is a part number), Framework in product_name.
    def self.best_guess(sources)
      sources.reject { |path, _| path.end_with?("board_name") }.values.max_by(&:length)
    end
  end
end
