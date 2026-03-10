require "open3"

module Dotlayer
  class Stow
    def initialize(target: "~", dry_run: false, verbose: false)
      @target = File.expand_path(target)
      @dry_run = dry_run
      @verbose = verbose
    end

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
      args << "-n" if @dry_run
      args << "-v" if @verbose
      args << "-d" << repo_path
      args << "-t" << @target

      if unstow
        args << "-D"
      elsif restow
        args << "-R"
      end

      args << package

      log(args.join(" "))

      return true if @dry_run

      output, status = Open3.capture2e(*args)
      unless status.success?
        warn "  \e[31mError stowing #{package}:\e[0m #{output.strip}"
      end
      status.success?
    end

    def log(message)
      puts "  \e[36m#{message}\e[0m" if @verbose || @dry_run
    end
  end
end
