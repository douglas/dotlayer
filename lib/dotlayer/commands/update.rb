require "open3"
require "rbconfig"

module Dotlayer
  module Commands
    # Pull dotlayer itself, the stowed repos and the `pull:` repos, re-stow,
    # then run the `after:` command of each `pull:` repo the pull changed.
    #
    # When dotlayer or a stowed repo changed, the rest runs in a fresh process
    # (new code, new dotlayer.yml): the old one may not understand the new
    # config, and this one loaded the config before pulling.
    class Update
      include Output

      SELF_ROOT = File.expand_path("../../..", __dir__)
      # Set on the re-run: the pull: repos the first run changed, one per line.
      PULLED_ENV = "DOTLAYER_PULLED".freeze

      def initialize(config:, detector: nil, dry_run: false, verbose: false, self_root: SELF_ROOT, env: ENV, reexec: nil)
        @config = config
        @detector = detector || Detector.new(config: @config)
        @dry_run = dry_run
        @verbose = verbose
        @self_root = self_root
        @env = env
        @reexec = reexec || method(:reexec)
      end

      # True when every pull and after: command succeeded.
      def run
        if @env.key?(PULLED_ENV)
          changed = @env.delete(PULLED_ENV).split("\n")
          @ok = true
        else
          changed = pull_repos
          return @reexec.call(changed) if @needs_reexec && !@dry_run
        end

        restow_packages
        run_after(changed)
        @ok
      end

      private

      def pull_repos
        heading "Pulling repos"
        @ok = true
        @needs_reexec = false

        restart = []
        restart << @self_root if self_repo?
        restart.concat(@config.repos.map(&:path))
        restart.uniq.each { |path| @needs_reexec = true if pull(path) }

        changed = @config.pull_repos.reject { |r| restart.include?(r.path) }.filter_map do |repo|
          repo.path if pull(repo.path)
        end

        puts
        changed
      end

      def self_repo?
        @self_root && Dir.exist?(File.join(@self_root, ".git"))
      end

      # Pulls one repo; true when it now has new commits.
      def pull(path)
        return false unless Dir.exist?(File.join(path, ".git"))

        print "  #{File.basename(path)}... "
        if @dry_run
          warning("dry-run")
          return false
        end

        before = head(path)
        output, status = Open3.capture2e("git", "-C", path, "pull", "--rebase")
        unless status.success?
          @ok = false
          error("failed")
          puts "    #{output.strip}"
          return false
        end

        changed = head(path) != before
        changed ? ok("updated") : ok("up to date")
        changed
      end

      def head(path)
        Open3.capture2("git", "-C", path, "rev-parse", "HEAD").first.strip
      end

      def run_after(changed)
        repos = @config.pull_repos.select(&:after)
        return if repos.empty?

        heading "After pull"
        repos.each do |repo|
          name = File.basename(repo.path)
          unless changed.include?(repo.path)
            puts "  #{name}: #{@dry_run ? "would run if the pull brings new commits" : "no new commits"} (#{repo.after})"
            next
          end

          puts "  #{name}: #{repo.after}"
          next if system("sh", "-c", repo.after, chdir: repo.path)

          @ok = false
          error("  after-pull failed: #{repo.after} (in #{repo.path})")
        end
        puts
      end

      def reexec(changed)
        args = [RbConfig.ruby, File.join(@self_root, "exe", "dotlayer"), "update"]
        args.push("-c", @config.path) if @config.path
        args << "-v" if @verbose
        puts "dotlayer or the dotfiles changed: continuing with the new version"
        exec({PULLED_ENV => changed.join("\n")}, *args)
      end

      def restow_packages
        detection = @detector.detect
        resolver = Resolver.new(config: @config, detection: detection)
        packages = resolver.resolve
        stow = Stow.new(target: @config.target, dry_run: @dry_run, verbose: @verbose)

        heading "Re-stowing packages"

        failures = packages.count do |repo_path, package|
          !restow_package(stow, repo_path, package, verb: "Restowing", target: @config.target_for(repo_path, package))
        end

        abort_failed_packages(failures) if failures.positive?

        puts
        puts "Done! #{packages.size} package(s) restowed."
      end

      def abort_failed_packages(failures)
        puts
        abort "Error: #{failures} package(s) failed to restow."
      end
    end
  end
end
