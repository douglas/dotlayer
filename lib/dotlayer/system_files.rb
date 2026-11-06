module Dotlayer
  # Compares configured system_files with what is on disk. Shared by `diff`
  # (reports) and `install` (installs only what is pending).
  module SystemFiles
    Change = Data.define(:source, :dest, :mode, :reason)

    DEFAULT_MODE = "0644".freeze

    # Returns a Change for every entry whose dest is missing, unreadable, or
    # differs from its source in content or mode.
    def self.pending(entries, repo)
      entries.filter_map { |entry| change_for(entry, repo) }
    end

    def self.change_for(entry, repo)
      source = File.expand_path(entry["source"], repo.path)
      dest = entry["dest"]
      mode = (entry["mode"] || DEFAULT_MODE).to_s
      reason = reason_for(source, dest, mode.to_i(8))
      Change.new(source:, dest:, mode:, reason:) if reason
    end

    def self.reason_for(source, dest, mode)
      return "source missing: #{source}" unless File.file?(source)
      return "missing" unless File.exist?(dest)

      reasons = []
      reasons << "content differs" unless File.binread(source) == File.binread(dest)
      actual_mode = File.stat(dest).mode & 0o7777
      reasons << format("mode %04o, want %04o", actual_mode, mode) unless actual_mode == mode
      reasons.join(", ") unless reasons.empty?
    rescue Errno::EACCES
      "unreadable, cannot compare"
    end
  end
end
