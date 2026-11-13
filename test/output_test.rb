require "test_helper"

class OutputTest < Minitest::Test
  include Dotlayer::Output

  def test_restow_package_failure_branch
    stow = Object.new
    stow.define_singleton_method(:dry_run?) { false }
    stow.define_singleton_method(:restow) { |_repo, _pkg| false }
    stow.define_singleton_method(:last_error) { "conflict found" }

    result = nil
    output = capture_io { result = restow_package(stow, "/repo", "pkg") }.first

    assert_match(/Stowing.*pkg/, output)
    assert_match(/failed.*conflict found/, output)
    assert_equal false, result
  end

  def test_restow_package_success_branch
    stow = Object.new
    stow.define_singleton_method(:dry_run?) { false }
    stow.define_singleton_method(:restow) { |_repo, _pkg| true }

    result = nil
    output = capture_io { result = restow_package(stow, "/repo", "pkg") }.first

    assert_match(/Stowing.*pkg/, output)
    assert_match(/ok/, output)
    assert_equal true, result
  end

  def test_restow_package_dry_run_branch
    stow = Object.new
    stow.define_singleton_method(:dry_run?) { true }
    stow.define_singleton_method(:restow) { |_repo, _pkg| true }

    output = capture_io { restow_package(stow, "/repo", "pkg") }.first

    assert_match(/Stowing.*pkg/, output)
    assert_match(/dry-run/, output)
  end

  def test_restow_package_custom_verb
    stow = Object.new
    stow.define_singleton_method(:dry_run?) { true }
    stow.define_singleton_method(:restow) { |_repo, _pkg| true }

    output = capture_io { restow_package(stow, "/repo", "pkg", verb: "Restowing") }.first

    assert_match(/Restowing.*pkg/, output)
  end

  def test_plain_output_has_no_escape_codes
    output = capture_io do
      heading "Title"
      ok
      error "bad"
      warning "careful"
      info "note"
      puts "#{green("g")} #{red("r")} #{yellow("y")} #{bold("b")} #{muted("m")}"
    end.first

    refute_match(/\e/, output)
    assert_equal "Title\nok\nbad\ncareful\nnote\ng r y b m\n", output
  end

  def test_no_color_env_keeps_a_tty_plain
    with_tty_stdout do
      ENV["NO_COLOR"] = "1"
      assert_equal "ok", green("ok")
    ensure
      ENV.delete("NO_COLOR")
    end
  end

  def test_tty_output_uses_marks_and_16_color_codes
    out = with_tty_stdout do
      heading "Title"
      ok
      error "  bad"
      warning "careful"
    end

    assert_equal "\e[1;34mTitle\e[0m\n\e[32m✓ ok\e[0m\n  \e[31m✗ bad\e[0m\n\e[33m● careful\e[0m\n", out
  end

  private

  def with_tty_stdout
    io = StringIO.new
    io.define_singleton_method(:tty?) { true }
    original = $stdout
    $stdout = io
    ENV["TERM"] = "xterm" if ENV["TERM"] == "dumb"
    yield
    io.string
  ensure
    $stdout = original
  end
end
