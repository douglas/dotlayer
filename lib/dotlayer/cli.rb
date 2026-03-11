require "optparse"

module Dotlayer
  class CLI
    def run(argv = ARGV)
      if argv.include?("--version")
        puts "dotlayer #{VERSION}"
        return
      end

      options = parse_global_options(argv)
      command = argv.shift
      config = Config.new(options[:config])

      case command
      when "status"  then Commands::Status.new(config:).run
      when "install" then Commands::Install.new(config:, dry_run: options[:dry_run], verbose: options[:verbose]).run
      when "update"  then Commands::Update.new(config:, dry_run: options[:dry_run], verbose: options[:verbose]).run
      when "doctor"  then Commands::Doctor.new(config:).run
      when "adopt"   then run_adopt(config:, argv:, options:)
      when "version"
        puts "dotlayer #{VERSION}"
      else
        print_usage
      end
    end

    private

    def parse_global_options(argv)
      options = { dry_run: false, verbose: false, config: nil, private: false }

      OptionParser.new do |opts|
        opts.on("-c", "--config PATH", "Config file path") { |v| options[:config] = v }
        opts.on("-n", "--dry-run", "Show what would be done") { options[:dry_run] = true }
        opts.on("-v", "--verbose", "Verbose output") { options[:verbose] = true }
        opts.on("-p", "--private", "Use private repo") { options[:private] = true }
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
          doctor    Check for broken symlinks, conflicts, missing deps
          adopt     Move config into a stow package and restow
          version   Print version

        Options:
          -c, --config PATH   Config file path (default: dotlayer.yml in repo)
          -n, --dry-run       Show what would be done without making changes
          -p, --private       Use private repo (for adopt command)
          -v, --verbose       Verbose output

        Examples:
          dotlayer adopt ~/.config/lazygit config
          dotlayer adopt ~/.config/lazygit ~/.config/lazydocker config
          dotlayer adopt --private ~/.config/lazysql config

      USAGE
    end
  end
end
