require "fileutils"

module Dotlayer
  # Clears what stow would refuse to overwrite, for `install --backup`.
  #
  # Candidates are the files a package ships. A candidate blocks stow when its
  # path under the target is a real file, or a link that points outside the
  # configured repos (links into a repo are stow's own). A real file identical
  # to the repo copy is deleted; anything else is moved to a per-run
  # ~/dotfiles-conflicts-<timestamp>/ directory, keeping its relative path.
  #
  # Stow's ignore rules are not re-implemented: when a candidate blocks, a
  # simulated stow run says which paths it would really refuse, and only those
  # are touched.
  class ConflictBackup
    include Output

    def initialize(config:, dry_run: false, now: Time.now)
      @config = config
      @dry_run = dry_run
      @backup_dir = File.join(config.target, "dotfiles-conflicts-#{now.strftime("%Y%m%d-%H%M%S")}")
      @removed = 0
      @moved = 0
      @handled = {}
    end

    # Resolves the conflicts of one package. Returns how many files it
    # removed or moved (or would, in dry-run).
    def resolve(repo_path, package, target: @config.target)
      pkg_dir = File.join(repo_path, package)
      return 0 unless Dir.exist?(pkg_dir)

      blockers = find_blockers(pkg_dir, target)
      return 0 if blockers.empty?

      refused = refused_paths(repo_path, package, target, blockers.keys)
      blockers.slice(*refused).count { |path, repo_file| clear(path, repo_file, target) }
    end

    def summary
      return if @removed.zero? && @moved.zero?

      verb = @dry_run ? "would be " : ""
      puts "  #{@removed} identical file(s) #{verb}removed, #{@moved} different file(s) #{verb}moved."
      puts "  Backups #{verb}in #{@backup_dir}. Compare them with the live links, then delete the folder." if @moved.positive?
    end

    private

    # {blocking path => repo file it blocks}
    def find_blockers(pkg_dir, target)
      repo_roots = @config.repos.map(&:path)
      candidates(pkg_dir).each_with_object({}) do |rel, found|
        repo_file = File.join(pkg_dir, rel)
        path = blocking_path(target, rel, repo_roots)
        next if path.nil? || @handled.key?(path) || File.identical?(path, repo_file)

        found[path] = repo_file
      end
    end

    # Files and links the package ships; real directories are not linked
    # themselves (a directory here is a git submodule or a parent).
    def candidates(pkg_dir)
      Dir.glob("**/*", File::FNM_DOTMATCH, base: pkg_dir).select do |rel|
        next false if %w[. ..].include?(File.basename(rel))

        full = File.join(pkg_dir, rel)
        File.symlink?(full) || !File.directory?(full)
      end
    end

    # The first path along rel under target that stops stow, or nil.
    def blocking_path(target, rel, repo_roots)
      parts = rel.split("/")
      parts.each_index do |i|
        path = File.join(target, *parts[0..i])
        return (foreign_link?(path, repo_roots) ? path : nil) if File.symlink?(path)
        return nil unless File.exist?(path)

        return path unless File.directory?(path)
      end
      nil
    end

    def foreign_link?(path, repo_roots)
      absolute = File.expand_path(File.readlink(path), File.dirname(path))
      repo_roots.none? { |root| absolute.start_with?("#{root}/") }
    end

    def refused_paths(repo_path, package, target, paths)
      stow = Stow.new(target:, dry_run: true, quiet: true)
      return [] if stow.restow(repo_path, package)

      output = stow.last_output.to_s
      paths.select do |path|
        rel = path.delete_prefix("#{target}/")
        output.match?(/(?:\A|\s)#{Regexp.escape(rel)}(?:\s|\z)/)
      end
    end

    def clear(path, repo_file, target)
      @handled[path] = true
      rel = path.delete_prefix("#{target}/")

      if identical_copy?(path, repo_file)
        warning "  #{@dry_run ? "would remove" : "removing"} identical file: #{rel}"
        FileUtils.rm(path) unless @dry_run
        @removed += 1
      else
        warning "  #{@dry_run ? "would move" : "moving"} to backup: #{rel}"
        move_to_backup(path) unless @dry_run
        @moved += 1
      end
      true
    end

    def identical_copy?(path, repo_file)
      !File.symlink?(path) && File.file?(path) && File.file?(repo_file) && FileUtils.compare_file(path, repo_file)
    end

    def move_to_backup(path)
      dest = File.join(@backup_dir, backup_relative(path))
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.mv(path, dest)
    end

    # Under the main target the path stays relative to it. A per-package
    # target elsewhere keeps its absolute path, so two targets never collide.
    def backup_relative(path)
      root = "#{@config.target}/"
      path.start_with?(root) ? path.delete_prefix(root) : path.delete_prefix("/")
    end
  end
end
