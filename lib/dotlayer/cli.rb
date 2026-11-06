require "optparse"

module Dotlayer
  class CLI
    def run(argv = ARGV)
      if argv.first == "--version"
        puts "dotlayer #{VERSION}"
        return
      end

      options = parse_global_options(argv)
      command = argv.shift
      config = Config.new(options[:config])

      case command
      when "status" then Commands::Status.new(config:).run
      when "install" then Commands::Install.new(
        config:, dry_run: options[:dry_run], verbose: options[:verbose], yes: options[:yes], backup: options[:backup]
      ).run
      when "update" then Commands::Update.new(config:, dry_run: options[:dry_run], verbose: options[:verbose]).run
      when "diff" then exit(1) unless Commands::Diff.new(config:).run
      when "doctor" then exit(1) unless Commands::Doctor.new(config:, max_depth: options[:depth]).run
      when "adopt" then run_adopt(config:, argv:, options:)
      when "version"
        puts "dotlayer #{VERSION}"
      else
        print_usage
      end
    end

    private

    def parse_global_options(argv)
      options = {dry_run: false, verbose: false, config: nil, private: false, depth: nil, yes: false, backup: false}

      OptionParser.new do |opts|
        opts.on("-c", "--config PATH", "Config file path") { |v| options[:config] = v }
        opts.on("-n", "--dry-run", "Show what would be done") { options[:dry_run] = true }
        opts.on("-v", "--verbose", "Verbose output") { options[:verbose] = true }
        opts.on("-y", "--yes", "Answer yes to install prompts (needed without a terminal)") { options[:yes] = true }
        opts.on("--backup", "install: move or delete files that block stow") { options[:backup] = true }
        opts.on("-p", "--private", "Use private repo") { options[:private] = true }
        opts.on("--depth N", Integer, "Max depth for doctor's dangling-link scan") { |v| options[:depth] = v }
      end.parse!(argv)

      options
    end

    def run_adopt(config:, argv:, options:)
      package = argv.pop
      paths = argv

      if paths.empty? || package.nil?
        abort "Usage: dotlayer adopt <path>... <package>"
      end

      Commands::Adopt.new(
        config:, paths:, package:,
        private_repo: options[:private],
        dry_run: options[:dry_run], verbose: options[:verbose]
      ).run
    end

    def print_usage
      puts <<~USAGE
        Usage: dotlayer [options] <command>

        Commands:
          install   Detect system, stow all layers, install system files
          update    Pull repos, re-stow all layers
          status    Show detected OS, profile, distros, and packages
          diff      Show what install would change (exit 1 if changes pending)
          doctor    Check for broken symlinks, conflicts, missing deps (exit 1 on issues)
          adopt     Move config into a stow package and restow
          version   Print version

        Options:
          -c, --config PATH   Config file path (default: dotlayer.yml in repo)
          -n, --dry-run       Show what would be done without making changes
          -y, --yes           Answer yes to install prompts (required when stdin is not a terminal)
              --backup        Install: delete identical blocking files, move others to ~/dotfiles-conflicts-<time>/
          -p, --private       Use private repo (for adopt command)
              --depth N       Max depth for doctor's dangling-link scan (default: 6)
          -v, --verbose       Verbose output

        Examples:
          dotlayer adopt ~/.config/lazygit config
          dotlayer adopt ~/.config/lazygit ~/.config/lazydocker config
          dotlayer adopt --private ~/.config/lazysql config

      USAGE
    end
  end
end
