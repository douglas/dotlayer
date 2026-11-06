require "test_helper"

class MachineAddTest < Minitest::Test
  include TestConfigHelper

  YAML_TEXT = <<~YAML
    # my config
    repos:
      - path: %<repo>s

    machines:
      env: DOTLAYER_MACHINE
      # the work laptop
      t14:
        detect: "true"

    distros:
      omarchy:
        detect: "true"
  YAML

  def setup
    @tmpdir = Dir.mktmpdir
    @repo = File.join(@tmpdir, "repo")
    @yml = File.join(@tmpdir, "dotlayer.yml")
    @layer = File.join(@repo, "config-omarchy-laptop-t14")
    FileUtils.mkdir_p([File.join(@layer, ".config", "hypr"), File.join(@repo, "config")])
    File.write(File.join(@layer, ".config", "hypr", "monitors.lua"), "monitors")
    File.write(File.join(@layer, ".config", "hypr", "input.lua"), "input")
    File.write(File.join(@layer, "run.sh"), "#!/bin/sh\n")
    File.chmod(0o755, File.join(@layer, "run.sh"))
    File.write(@yml, format(YAML_TEXT, repo: @repo))
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_adds_the_rule_text_and_copies_the_layer_without_monitors
    output = add("p14s", match: "ThinkPad P14s", from: "t14")

    dest = File.join(@repo, "config-omarchy-laptop-p14s")
    assert_equal "input", File.read(File.join(dest, ".config", "hypr", "input.lua"))
    refute File.exist?(File.join(dest, ".config", "hypr", "monitors.lua"))
    assert File.executable?(File.join(dest, "run.sh"))
    assert_equal <<~YAML, File.read(@yml)
      # my config
      repos:
        - path: #{@repo}

      machines:
        env: DOTLAYER_MACHINE
        # the work laptop
        t14:
          detect: "true"
        p14s:
          model: "ThinkPad P14s"

      distros:
        omarchy:
          detect: "true"
    YAML
    assert_match(/p14s \(laptop\), matched by model containing "ThinkPad P14s"/, output)
    assert Dotlayer::Config.new(@yml).machines.key?("p14s")
  end

  def test_default_match_is_the_longest_model_field
    model = {"/sys/class/dmi/id/product_name" => "21RV000NUS", "/sys/class/dmi/id/product_version" => "ThinkPad P14s Gen 6 AMD"}

    add("p14s", detection: build_detection(model:, profile: "laptop", distros: ["omarchy"]))

    assert_match(/model: "ThinkPad P14s Gen 6 AMD"/, File.read(@yml))
  end

  def test_dry_run_writes_nothing
    before = File.read(@yml)

    output = add("p14s", match: "X", from: "t14", dry_run: true)

    assert_match(/Dry run: nothing written/, output)
    assert_equal before, File.read(@yml)
    refute File.exist?(File.join(@repo, "config-omarchy-laptop-p14s"))
  end

  def test_refuses_existing_machine_and_layer
    assert_aborts(/already has machine t14/) { run_add("t14", match: "X") }
    FileUtils.mkdir_p(File.join(@repo, "config-omarchy-laptop-new"))
    assert_aborts(/layer already exists/) { run_add("new", match: "X") }
  end

  def test_rejects_quotes_bad_names_and_missing_source_layer
    assert_aborts(/quotes/) { run_add("p14s", match: 'a"b') }
    assert_aborts(/quotes/) { run_add("p14s", match: "a'b") }
    assert_aborts(/lowercase/) { run_add("P14S", match: "X") }
    assert_aborts(/no layer to copy/) { run_add("p14s", match: "X", from: "nope") }
    assert_aborts(/profile must be/) { run_add("p14s", match: "X", profile: "tablet") }
  end

  def test_several_distros_need_an_explicit_choice
    detection = build_detection(profile: "laptop", distros: %w[omarchy arch])

    assert_aborts(/pass --distro/) { run_add("p14s", match: "X", detection:) }
    add("p14s", match: "X", detection:, distro: "arch")
    assert File.directory?(File.join(@repo, "config-arch-laptop-p14s"))
  end

  def test_without_a_distro_the_layer_is_a_plain_machine_layer
    add("p14s", match: "X", detection: build_detection(profile: "laptop", distros: []))

    assert File.directory?(File.join(@repo, "config-p14s"))
  end

  def test_insert_rule_creates_a_machines_block_when_missing
    text = Dotlayer::Commands::MachineAdd.insert_rule("target: ~", ["  a:\n", "    model: \"X\"\n"])

    assert_equal "target: ~\n\nmachines:\n  a:\n    model: \"X\"\n", text
  end

  def test_insert_rule_handles_a_block_at_the_end_of_the_file
    text = Dotlayer::Commands::MachineAdd.insert_rule("machines:\n  a:\n    detect: x\n\n", ["  b:\n", "    model: \"X\"\n"])

    assert_equal "machines:\n  a:\n    detect: x\n  b:\n    model: \"X\"\n\n", text
  end

  def test_cli_routes_machine_add
    capture_io {
      Dotlayer::CLI.new.run(["-c", @yml, "machine", "add", "p14s", "--match", "P14s", "--profile", "laptop", "--distro", "omarchy", "--from", "t14"])
    }

    assert File.directory?(File.join(@repo, "config-omarchy-laptop-p14s"))
    assert_match(/p14s:\n    model: "P14s"/, File.read(@yml))
  end

  private

  def add(...)
    capture_io { run_add(...) }.first
  end

  def run_add(name, detection: build_detection(profile: "laptop", distros: ["omarchy"]), **options)
    config = Dotlayer::Config.new(@yml)
    Dotlayer::Commands::MachineAdd.new(config:, name:, detector: stub_detector(detection), **options).run
  end

  def assert_aborts(pattern)
    stderr = capture_io { assert_raises(SystemExit) { yield } }.last
    assert_match(pattern, stderr)
  end
end
