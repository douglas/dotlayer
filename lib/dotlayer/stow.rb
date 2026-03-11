require "open3"

module Dotlayer
  class Stow
    attr_reader :last_error

    def initialize(target: "~", dry_run: false, verbose: false)
      @target = File.expand_path(target)
      @dry_run = dry_run
      @verbose = verbose
    end

    def dry_run? = @dry_run

    def restow(repo_path, package)
      run_stow(repo_path, package)
    end

    private

    def run_stow(repo_path, package)
      args = ["stow", "-R"]
      args << "-v" if @verbose
      args << "-d" << repo_path
      args << "-t" << @target
      args << package

      if @verbose || @dry_run
        $stderr.puts "  #{args.join(" ")}"
      end

      return true if @dry_run

      output, status = Open3.capture2e(*args)
      @last_error = status.success? ? nil : output.strip
      status.success?
    rescue Errno::ENOENT
      @last_error = "GNU Stow is not installed. Install it with your package manager."
      false
    end
  end
end
