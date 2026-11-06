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
      SOURCES.each_with_object({}) do |relative, found|
        text = File.read(File.join(root, relative)).delete("\0").strip
        found["/#{relative}"] = text unless text.empty? || PLACEHOLDERS.include?(text)
      rescue SystemCallError
        next
      end
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
