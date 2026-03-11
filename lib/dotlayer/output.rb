module Dotlayer
  module Output
    def heading(text)
      puts "\e[1m#{text}\e[0m"
    end

    def ok(text = "ok")
      puts "\e[32m#{text}\e[0m"
    end

    def error(text)
      puts "\e[31m#{text}\e[0m"
    end

    def warn_text(text)
      puts "\e[33m#{text}\e[0m"
    end

    def info(text)
      puts "\e[36m#{text}\e[0m"
    end

    def green(text)
      "\e[32m#{text}\e[0m"
    end

    def red(text)
      "\e[31m#{text}\e[0m"
    end

    def yellow(text)
      "\e[33m#{text}\e[0m"
    end

    def bold(text)
      "\e[1m#{text}\e[0m"
    end

    def restow_package(stow, repo_path, package, verb: "Stowing")
      print "  #{verb} #{green(package)}... "
      if stow.dry_run?
        warn_text("dry-run")
      elsif stow.restow(repo_path, package)
        ok
      else
        error("failed: #{stow.last_error}")
      end
    end
  end
end
