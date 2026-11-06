require "fileutils"
require "open3"
require "shellwords"

module Dotlayer
  module Commands
    # `dotlayer hooks install|uninstall`: git hooks that re-stow after a pull.
    # post-merge covers `git pull`, post-rewrite covers `git pull --rebase`.
    # #run returns false when a foreign hook was left alone.
    class Hooks
      include Output

      MARKER = "# dotlayer-managed-hook".freeze
      NAMES = %w[post-merge post-rewrite].freeze

      def initialize(config:, action:, dry_run: false)
        @config = config
        @action = action
        @dry_run = dry_run
        @refused = false
      end

      def run
        heading "Git hooks (#{@action})"
        @config.repos.each { |repo| handle_repo(repo.path) }
        !@refused
      end

      def self.script(name, config_path: nil)
        install = ["dotlayer"]
        install += ["-c", config_path] if config_path
        install += ["install", "--quiet"]
        guard = (name == "post-rewrite") ? "[ \"$1\" = rebase ] || exit 0\n" : ""
        <<~SH
          #!/bin/sh
          #{MARKER}: written by `dotlayer hooks install`, removed by `dotlayer hooks uninstall`.
          # Re-stows after a pull. It never prompts: pending system files are only reported.
          #{guard}command -v dotlayer >/dev/null 2>&1 || exit 0
          exec #{install.shelljoin} </dev/null
        SH
      end

      private

      def handle_repo(repo_path)
        puts "  #{File.basename(repo_path)}"
        return puts("    missing, skipped") unless Dir.exist?(repo_path)

        hooks_dir = hooks_dir(repo_path)
        return puts("    not a git repo, skipped") unless hooks_dir

        custom = git(repo_path, "config", "--get", "core.hooksPath")
        return hooks_path_set(custom) unless custom.empty?

        NAMES.each { |name| (@action == "install") ? install_hook(hooks_dir, name) : remove_hook(hooks_dir, name) }
      end

      def hooks_dir(repo_path)
        path = git(repo_path, "rev-parse", "--git-path", "hooks")
        path.empty? ? nil : File.expand_path(path, repo_path)
      end

      def git(repo_path, *args)
        output, status = Open3.capture2("git", "-C", repo_path, *args, err: File::NULL)
        status.success? ? output.strip : ""
      rescue SystemCallError
        ""
      end

      def hooks_path_set(path)
        if @action == "install"
          warning "    core.hooksPath is set (#{path}): not writing hooks. Add this to #{NAMES.join(" and ")} there:"
          puts "      dotlayer install --quiet </dev/null   # post-rewrite: only when $1 is \"rebase\""
        else
          puts "    core.hooksPath is set (#{path}): nothing was written by dotlayer, left alone"
        end
      end

      def install_hook(dir, name)
        path = File.join(dir, name)
        content = self.class.script(name, config_path: explicit_config_path)

        if File.exist?(path) || File.symlink?(path)
          unless File.read(path).include?(MARKER)
            @refused = true
            return error("    #{name}: a hook that dotlayer did not write already exists, refusing to touch it: #{path}")
          end
          return puts("    #{name}: already installed") if File.read(path) == content

          puts "    #{name}: updating"
        else
          puts "    #{name}: installing"
        end
        write(path, content)
      end

      def remove_hook(dir, name)
        path = File.join(dir, name)
        return puts("    #{name}: not installed") unless File.exist?(path)
        return puts("    #{name}: not written by dotlayer, left alone") unless File.read(path).include?(MARKER)

        puts "    #{name}: removing"
        File.delete(path) unless @dry_run
      end

      def write(path, content)
        return if @dry_run

        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
        File.chmod(0o755, path)
      end

      # Only a config the user named with -c is baked into the hook; the
      # default discovery works the same when git runs it.
      def explicit_config_path
        @config.path if @config.source == "-c"
      end
    end
  end
end
