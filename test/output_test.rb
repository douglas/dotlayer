require "test_helper"

class OutputTest < Minitest::Test
  include Dotlayer::Output

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
