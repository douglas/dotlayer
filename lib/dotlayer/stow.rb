require "open3"

module Dotlayer
  class Stow
    GLOBAL_IGNORE = ".stow-global-ignore".freeze
    GLOBAL_IGNORE_NOTE = "A package ships ~/#{GLOBAL_IGNORE}, which is not linked yet. " \
      "Stow reads it from $HOME, so until install links it, a simulation uses " \
      "stow's built-in ignore list and can miss conflicts (such as .gitignore) that install will hit.".freeze

    # Packages that ship a global ignore list Stow cannot see yet. Stow reads
    # $HOME/.stow-global-ignore, and install links it before later packages,
    # so simulating every package up front (diff, doctor) uses the wrong list.
    def self.pending_global_ignore(packages, home: ENV.fetch("HOME", Dir.home))
      live = File.join(home, GLOBAL_IGNORE)
      packages.select do |repo_path, package|
        file = File.join(repo_path, package, GLOBAL_IGNORE)
        File.exist?(file) && !(File.exist?(live) && File.identical?(live, file))
      end
    end

    attr_reader :last_error, :last_output

    def initialize(target: "~", dry_run: false, verbose: false, quiet: false)
      @target = File.expand_path(target)
      @dry_run = dry_run
      @verbose = verbose
      @quiet = quiet
    end

    def dry_run? = @dry_run

    def restow(repo_path, package)
      args = ["stow", "-R", "--no-folding"]
      args << "-n" if @dry_run
      args << "-v" if @verbose
      args << "-d" << repo_path
      args << "-t" << @target
      args << package

      if !@quiet && (@verbose || @dry_run)
        warn "  #{args.join(" ")}"
      end

      output, status = Open3.capture2e(*args)
      @last_output = output
      @last_error = status.success? ? nil : output.strip
      status.success?
    rescue Errno::ENOENT
      @last_error = "GNU Stow is not installed. Install it with your package manager."
      false
    end
  end
end
