require "shellwords"

module Dotlayer
  module Commands
    class Doctor
      include Output

      DEFAULT_MAX_DEPTH = 6
      SKIP_DIRS = %w[.cache node_modules .git].freeze
      SKIP_PATHS = %w[.local/share/Steam .local/state].freeze

      def initialize(config:, detector: nil, max_depth: nil)
        @config = config
        @max_depth = max_depth || DEFAULT_MAX_DEPTH
        @detector = detector || Detector.new(config: @config)
        @issues = []
        @reported_links = []
        @hints = []
      end

      def run
        detection = @detector.detect
        resolver = Resolver.new(config: @config, detection: detection)
        @packages = resolver.resolve

        heading "Dotlayer Doctor"
        puts

        check_stow_installed
        check_repos_exist
        check_packages_exist(@packages)
        check_broken_symlinks
        check_unlinked_files
        check_dangling_repo_links

        puts
        if @issues.empty?
          ok "No issues found."
        else
          error "#{@issues.size} issue(s) found:"
          @issues.each { |issue| puts "  - #{issue}" }
          @hints.each { |hint| puts "  #{hint}" }
        end
        @issues.empty?
      end

      private

      def check_stow_installed
        print "  Checking stow... "
        if (@stow_installed = system("which", "stow", out: File::NULL, err: File::NULL))
          ok "installed"
        else
          error "missing"
          @issues << "GNU Stow is not installed"
        end
      end

      def check_repos_exist
        @config.repos.each do |repo|
          print "  Checking repo #{repo.path}... "
          if Dir.exist?(repo.path)
            ok "exists"
          else
            error "missing"
            @issues << "Repo not found: #{repo.path}"
          end
        end
      end

      def check_packages_exist(packages)
        packages.each do |repo_path, package|
          pkg_path = File.join(repo_path, package)
          unless Dir.exist?(pkg_path)
            @issues << "Package directory missing: #{pkg_path}"
          end
        end
      end

      def check_broken_symlinks
        print "  Checking for broken symlinks in managed config paths... "
        broken = find_broken_symlinks
        if broken.empty?
          ok "none"
        else
          warning "#{broken.size} found"
          broken.each do |link|
            target = begin
              File.readlink(link)
            rescue
              "(deleted)"
            end
            @issues << "Broken symlink: #{link} -> #{target}"
            @reported_links << link
          end
        end
      end

      # Tools that save by writing a temp file and renaming it (or `sed -i`)
      # replace a stowed link with a plain file, and the repo stops reaching
      # the machine. Stow's simulate mode reports those as conflicts, so ask
      # it instead of re-implementing its ignore rules.
      def check_unlinked_files
        return unless @stow_installed

        print "  Checking that managed files are still links... "
        stow = Stow.new(target: @config.target, dry_run: true, quiet: true)
        conflicts = @packages.flat_map { |repo_path, package|
          next [] if !Dir.exist?(File.join(repo_path, package)) ||
            stow.restow(repo_path, package, target: @config.target_for(repo_path, package))

          conflicts = stow.last_output.to_s.each_line(chomp: true).filter_map { |line| Diff::CONFLICT_LINE.match(line)&.[](1) }
          conflicts = [stow.last_error] if conflicts.empty?
          conflicts.map { |conflict| [repo_path, package, conflict] }
        }

        if conflicts.empty?
          ok "yes"
          warning "    Note: #{Stow::GLOBAL_IGNORE_NOTE}" if Stow.pending_global_ignore(@packages).any?
          return
        end

        warning "#{conflicts.size} not linked"
        conflicts.each do |repo_path, package, conflict|
          @issues << "#{File.basename(repo_path)}/#{package}: #{conflict}"
        end
        @hints << "Compare each file with its repo copy (dotlayer diff lists them), keep what you need, delete the plain file, then run dotlayer install."
      end

      # Report-only scan of the whole target dir for links into a configured
      # repo whose destination no longer exists. Never follows directory
      # symlinks and never deletes anything.
      def check_dangling_repo_links
        print "  Checking for dangling links into repos (depth #{@max_depth})... "
        dangling = find_dangling_repo_links(scan_roots)
        if dangling.empty?
          ok "none"
          return
        end

        warning "#{dangling.size} found"
        dangling.each do |link, target|
          @issues << "Dangling link into repo: #{link} -> #{target}"
        end
        @hints << "To remove dangling links: rm #{dangling.keys.map { |link| Shellwords.escape(link) }.join(" ")}"
      end

      # The global target plus every per-package target, minus targets that
      # sit inside another root (the scan already reaches them).
      def scan_roots
        roots = ([@config.target] + @packages.map { |repo_path, package| @config.target_for(repo_path, package) }).uniq
        roots.reject { |root| roots.any? { |other| other != root && root.start_with?("#{other}/") } }
      end

      def find_dangling_repo_links(roots)
        repo_roots = @config.repos.map(&:path)
        @shipped_dirs = shipped_dirs(repo_roots)
        found = {}
        roots.each { |root| scan_dir(root, root, 0, repo_roots, found) }
        found.except(*@reported_links)
      end

      def scan_dir(dir, root, depth, repo_roots, found)
        Dir.children(dir).sort.each do |name|
          path = File.join(dir, name)
          if File.symlink?(path)
            target = File.readlink(path)
            absolute = File.expand_path(target, dir)
            found[path] = target if into_repo?(absolute, repo_roots) && !File.exist?(path)
          elsif File.directory?(path) && depth < @max_depth && !skip_dir?(path, root, repo_roots)
            scan_dir(path, root, depth + 1, repo_roots, found)
          end
        end
      rescue SystemCallError
        nil
      end

      def into_repo?(path, repo_roots)
        repo_roots.any? { |repo| path.start_with?("#{repo}/") }
      end

      def skip_dir?(path, root, repo_roots)
        relative = path.delete_prefix("#{root}/")
        SKIP_DIRS.include?(File.basename(path)) ||
          SKIP_PATHS.include?(relative) ||
          repo_roots.include?(path) ||
          foreign_checkout?(path)
      end

      # Another git checkout (~/src/*, ~/work/*) holds stow links only where a
      # package ships files into it, so skip it otherwise. Checkouts are most
      # of the files under a home dir, and the scan is far faster without them.
      def foreign_checkout?(path)
        File.exist?(File.join(path, ".git")) && !@shipped_dirs.include?(path)
      end

      # Every directory any package in the repos ships, as an absolute path
      # under that package's own target. Covers packages that don't apply to
      # this machine, since their old links can still dangle here.
      def shipped_dirs(repo_roots)
        repo_roots.flat_map { |repo|
          Dir.glob("*/", base: repo).flat_map do |package|
            package = package.chomp("/")
            target = @config.target_for(repo, package)
            Dir.glob("**/", File::FNM_DOTMATCH, base: File.join(repo, package))
              .map { |dir| dir.chomp("/") }
              .reject { |dir| dir == "." }
              .map { |dir| File.join(target, dir) }
          end
        }.to_set
      end

      def find_broken_symlinks
        broken = []
        managed_roots = [".config", ".local"]
        scan_paths = @packages.flat_map { |repo_path, package|
          pkg_dir = File.join(repo_path, package)
          next [] unless Dir.exist?(pkg_dir)

          target = @config.target_for(repo_path, package)

          managed_roots.flat_map do |root_name|
            root_path = File.join(pkg_dir, root_name)
            next [] unless File.exist?(root_path) || File.symlink?(root_path)

            managed_paths = [root_path]
            if File.directory?(root_path)
              managed_paths.concat(Dir.glob(File.join(root_path, "**", "*"), File::FNM_DOTMATCH))
            end

            managed_paths
              .reject { |path| [".", ".."].include?(File.basename(path)) }
              .map { |path| File.join(target, path.delete_prefix("#{pkg_dir}/")) }
          end
        }.uniq

        scan_paths.each do |path|
          broken << path if File.symlink?(path) && !File.exist?(path)
        end

        broken
      end
    end
  end
end
