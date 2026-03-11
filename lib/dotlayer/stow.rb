require "open3"

module Dotlayer
  class Stow
    def initialize(target: "~", dry_run: false, verbose: false)
      @target = File.expand_path(target)
      @dry_run = dry_run
      @verbose = verbose
    end

    def dry_run? = @dry_run

    def stow(repo_path, package)
      run_stow(repo_path, package)
    end

    def restow(repo_path, package)
      run_stow(repo_path, package, restow: true)
    end

    def unstow(repo_path, package)
      run_stow(repo_path, package, unstow: true)
    end

    private

    def run_stow(repo_path, package, restow: false, unstow: false)
      args = ["stow"]
      args << "-v" if @verbose
      args << "-d" << repo_path
      args << "-t" << @target

      if unstow
        args << "-D"
      elsif restow
        args << "-R"
      end

      args << package

      if @verbose || @dry_run
        $stderr.puts "  \e[36m#{args.join(" ")}\e[0m"
      end

      return true if @dry_run

      output, status = Open3.capture2e(*args)
      @last_error = output.strip unless status.success?
      status.success?
    rescue Errno::ENOENT
      @last_error = "GNU Stow is not installed. Install it with your package manager."
      false
    end
  end
end
