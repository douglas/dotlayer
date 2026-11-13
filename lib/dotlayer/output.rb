require "stringio"

module Dotlayer
  module Output
    # Runs the block with stdout swallowed, so --json prints only the JSON.
    def silence_stdout
      original = $stdout
      $stdout = StringIO.new
      yield
    ensure
      $stdout = original
    end

    # Color and marks only on a terminal; piped output (scripts, CI) and
    # NO_COLOR stay plain. Only the 16-color palette, so the terminal theme
    # decides the actual colors.
    def color?
      $stdout.tty? && ENV.fetch("NO_COLOR", "").empty? && ENV["TERM"] != "dumb"
    end

    def paint(code, text)
      color? ? "\e[#{code}m#{text}\e[0m" : text.to_s
    end

    # Puts the mark after any leading indent, and only on a terminal.
    def mark_line(code, mark, text)
      indent, rest = text.to_s.match(/\A(\s*)(.*)\z/m).captures
      puts color? ? "#{indent}#{paint(code, "#{mark} #{rest}")}" : text
    end

    def heading(text)
      puts paint("1;34", text)
    end

    def ok(text = "ok")
      mark_line(32, "✓", text)
    end

    def error(text)
      mark_line(31, "✗", text)
    end

    def warning(text)
      mark_line(33, "●", text)
    end

    def info(text)
      puts paint(90, text)
    end

    def green(text)
      paint(32, text)
    end

    def red(text)
      paint(31, text)
    end

    def yellow(text)
      paint(33, text)
    end

    def bold(text)
      paint(1, text)
    end

    def muted(text)
      paint(90, text)
    end

    def restow_package(stow, repo_path, package, verb: "Stowing", target: nil)
      print "  #{verb} #{green(package)}... "
      options = target ? {target:} : {}
      if stow.restow(repo_path, package, **options)
        stow.dry_run? ? warning("dry-run") : ok
        true
      else
        error("failed: #{stow.last_error}")
        false
      end
    end
  end
end
