require "test_helper"

class ModelTest < Minitest::Test
  HW = File.expand_path("fixtures/hw", __dir__)

  def test_reads_every_non_empty_dmi_source
    model = Dotlayer::Model.read(root: File.join(HW, "lenovo"))

    assert_equal "21RV000NUS", model["/sys/class/dmi/id/product_name"]
    assert_equal "ThinkPad P14s Gen 6 AMD", model["/sys/class/dmi/id/product_version"]
    assert_equal "21RV000NUS", model["/sys/class/dmi/id/board_name"]
  end

  def test_reads_device_tree_model_without_nuls
    model = Dotlayer::Model.read(root: File.join(HW, "apple"))

    assert_equal({"/proc/device-tree/model" => "Apple MacBook Pro (14-inch, 2023)"}, model)
  end

  def test_missing_root_reads_nothing
    assert_empty Dotlayer::Model.read(root: "/nonexistent")
  end

  def test_ignores_placeholder_values
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "sys/class/dmi/id"))
      File.write(File.join(root, "sys/class/dmi/id/product_name"), "Default string\n")
      File.write(File.join(root, "sys/class/dmi/id/product_version"), "  \n")

      assert_empty Dotlayer::Model.read(root:)
    end
  end

  def test_match_is_a_case_sensitive_substring_of_any_source
    model = Dotlayer::Model.read(root: File.join(HW, "lenovo"))

    assert Dotlayer::Model.match?(model, "P14s")
    assert Dotlayer::Model.match?(model, ["nope", "21RV000NUS"])
    refute Dotlayer::Model.match?(model, "p14S")
    refute Dotlayer::Model.match?(model, ["T14"])
  end

  def test_best_guess_is_the_longest_field_ignoring_board_name
    assert_equal "ThinkPad P14s Gen 6 AMD", Dotlayer::Model.best_guess(Dotlayer::Model.read(root: File.join(HW, "lenovo")))
    assert_equal "Laptop 13 (AMD Ryzen 7040Series)", Dotlayer::Model.best_guess(Dotlayer::Model.read(root: File.join(HW, "framework")))
    assert_equal "Apple MacBook Pro (14-inch, 2023)", Dotlayer::Model.best_guess(Dotlayer::Model.read(root: File.join(HW, "apple")))
  end
end
