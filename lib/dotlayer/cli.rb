require "optparse"

module Dotlayer
  class CLI
    def run(argv = ARGV)
      options = parse_global_options(argv)
      command = argv.shift
      config = Config.new(options[:config])

      case command
      when "status"  then Commands::Status.new(config:).run
      when "install" then Commands::Install.new(config:, dry_run: options[:dry_run], verbose: options[:verbose]).run
      when "update"  then Commands::Update.new(config:, dry_run: options[:dry_run], verbose: options[:verbose]).run
      when "doctor"  then Commands::Doctor.new(config:).run
      when "version", "--version", "-v"
        puts "dotlayer #{VERSION}"
      else
        print_usage
      end
    end

    private

    def parse_global_options(argv)
      options = { dry_run: false, verbose: false, config: nil }

      OptionParser.new do |opts|
        opts.on("-c", "--config PATH", "Config file path") { |v| options[:config] = v }
        opts.on("-n", "--dry-run", "Show what would be done") { options[:dry_run] = true }
        opts.on("-v", "--verbose", "Verbose output") { options[:verbose] = true }
      end.order!(argv)

      options
    end

    def print_usage
      puts <<~USAGE
        Usage: dotlayer [options] <command>

        Commands:
          install   Detect system, stow all layers, install system files
          update    Pull repos, re-stow all layers
          status    Show detected OS, profile, frameworks, and packages
          doctor    Check for broken symlinks, conflicts, missing deps
          version   Print version

        Options:
          -c, --config PATH   Config file path (default: dotlayer.yml in repo)
          -n, --dry-run       Show what would be done without making changes
          -v, --verbose       Verbose output

      USAGE
    end
  end
end
