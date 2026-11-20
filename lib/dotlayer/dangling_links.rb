module Dotlayer
  # Symlinks under the stow target(s) that point into a configured repo whose
  # destination no longer exists. `stow -R` leaves them behind when a file is
  # deleted from a repo. Never follows directory symlinks.
  class DanglingLinks
    include Output

    DEFAULT_MAX_DEPTH = 6
    SKIP_DIRS = %w[.cache node_modules .git].freeze
    SKIP_PATHS = %w[.local/share/Steam .local/state].freeze
    # macOS guards these home folders with privacy prompts, and reading one
    # waits until someone answers, which never happens over SSH. The scan
    # enters them only on the way to a directory a package ships.
    MACOS_PRIVATE_DIRS = %w[Applications Desktop Documents Downloads Library Movies Music OrbStack Pictures Public].freeze

    def initialize(config:, packages:, macos: false, max_depth: nil)
      @config = config
      @packages = packages
      @macos = macos
      @max_depth = max_depth || DEFAULT_MAX_DEPTH
    end

    # {link path => raw link target}
    def find
      repo_roots = @config.repos.map(&:path)
      @shipped_dirs = shipped_dirs(repo_roots)
      @shipped_paths = @shipped_dirs.flat_map { |dir| ancestors(dir) }.to_set
      found = {}
      roots.each { |root| scan_dir(root, root, 0, repo_roots, found) }
      found
    end

    # Removes the dangling links, then the parent directories that are left
    # empty, never a top-level directory of the target (so never ~/.config).
    # With dry_run it only prints. Returns the links removed (or that would be).
    def prune(dry_run: false, links: find.keys)
      links.each do |link|
        if dry_run
          puts "  would remove #{link}"
        else
          File.unlink(link)
          puts "  removed #{link}"
          remove_empty_parents(link)
        end
      rescue SystemCallError => e
        error("  could not remove #{link}: #{e.message}")
      end
      links
    end

    # The global target plus every per-package target, minus targets that
    # sit inside another root (the scan already reaches them).
    def roots
      all = ([@config.target] + @packages.map { |repo_path, package| @config.target_for(repo_path, package) }).uniq
      all.reject { |root| all.any? { |other| other != root && root.start_with?("#{other}/") } }
    end

    private

    def remove_empty_parents(link)
      root = roots.select { |r| link.start_with?("#{r}/") }.max_by(&:length)
      return unless root

      dir = File.dirname(link)
      # A dir directly under the root is a top-level dir: keep it.
      while File.dirname(dir) != root && dir.start_with?("#{root}/") && Dir.empty?(dir)
        Dir.rmdir(dir)
        puts "  removed empty directory #{dir}"
        dir = File.dirname(dir)
      end
    rescue SystemCallError
      nil
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
        foreign_checkout?(path) ||
        macos_private?(path, relative)
    end

    def macos_private?(path, relative)
      @macos && MACOS_PRIVATE_DIRS.include?(relative.split("/").first) && !@shipped_paths.include?(path)
    end

    # dir and every directory above it.
    def ancestors(dir)
      Enumerator.produce(dir) { |d| File.dirname(d) }.take_while { |d| d != File.dirname(d) }
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
  end
end
