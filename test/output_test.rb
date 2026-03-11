require "test_helper"

class OutputTest < Minitest::Test
  include Dotlayer::Output

  def test_green_wraps_in_ansi
    assert_equal "\e[32mhello\e[0m", green("hello")
  end

  def test_red_wraps_in_ansi
    assert_equal "\e[31mhello\e[0m", red("hello")
  end

  def test_yellow_wraps_in_ansi
    assert_equal "\e[33mhello\e[0m", yellow("hello")
  end

  def test_bold_wraps_in_ansi
    assert_equal "\e[1mhello\e[0m", bold("hello")
  end

  def test_heading_prints_bold
    output = capture_io { heading("Title") }.first
    assert_equal "\e[1mTitle\e[0m\n", output
  end

  def test_ok_prints_green
    output = capture_io { ok }.first
    assert_equal "\e[32mok\e[0m\n", output
  end

  def test_ok_with_custom_text
    output = capture_io { ok("done") }.first
    assert_equal "\e[32mdone\e[0m\n", output
  end

  def test_error_prints_red
    output = capture_io { error("broken") }.first
    assert_equal "\e[31mbroken\e[0m\n", output
  end

  def test_warn_text_prints_yellow
    output = capture_io { warn_text("caution") }.first
    assert_equal "\e[33mcaution\e[0m\n", output
  end

  def test_info_prints_cyan
    output = capture_io { info("note") }.first
    assert_equal "\e[36mnote\e[0m\n", output
  end

  def test_restow_package_failure_branch
    stow = Object.new
    stow.define_singleton_method(:dry_run?) { false }
    stow.define_singleton_method(:restow) { |_repo, _pkg| false }
    stow.define_singleton_method(:last_error) { "conflict found" }

    output = capture_io { restow_package(stow, "/repo", "pkg") }.first

    assert_match(/Stowing.*pkg/, output)
    assert_match(/failed.*conflict found/, output)
  end

  def test_restow_package_success_branch
    stow = Object.new
    stow.define_singleton_method(:dry_run?) { false }
    stow.define_singleton_method(:restow) { |_repo, _pkg| true }

    output = capture_io { restow_package(stow, "/repo", "pkg") }.first

    assert_match(/Stowing.*pkg/, output)
    assert_match(/ok/, output)
  end

  def test_restow_package_dry_run_branch
    stow = Object.new
    stow.define_singleton_method(:dry_run?) { true }

    output = capture_io { restow_package(stow, "/repo", "pkg") }.first

    assert_match(/Stowing.*pkg/, output)
    assert_match(/dry-run/, output)
  end

  def test_restow_package_custom_verb
    stow = Object.new
    stow.define_singleton_method(:dry_run?) { true }

    output = capture_io { restow_package(stow, "/repo", "pkg", verb: "Restowing") }.first

    assert_match(/Restowing.*pkg/, output)
  end
end
