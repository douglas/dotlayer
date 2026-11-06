require "test_helper"
require "json"

# --json for status, diff and doctor, through the CLI: stdout must be exactly
# one JSON document, with no ANSI codes.
class JsonTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @target = File.join(@tmpdir, "home")
    @repo = File.join(@tmpdir, "repo")
    @codex = File.join(@tmpdir, "codex-home")
    FileUtils.mkdir_p([File.join(@repo, "config", ".config", "app"), File.join(@repo, "codex"), File.join(@repo, ".system"), @target, @codex])
    File.write(File.join(@repo, "config", ".config", "app", "settings"), "repo")
    File.write(File.join(@repo, "codex", "config.toml"), "x")
    File.write(File.join(@repo, ".system", "test.conf"), "sys")
    @config_path = File.join(@tmpdir, "dotlayer.yml")
    File.write(@config_path, <<~YAML)
      target: #{@target}
      repos:
        - path: #{@repo}
      packages:
        - config
        - {name: codex, target: #{@codex}}
      system_files:
        - source: .system/test.conf
          dest: #{@tmpdir}/etc/test.conf
    YAML
    @home = ENV["HOME"]
    ENV["HOME"] = @tmpdir
  end

  def teardown
    ENV["HOME"] = @home
    FileUtils.rm_rf(@tmpdir)
  end

  def test_status_json
    json, = run_json("status")

    assert_equal %w[config distros groups machine model os packages profile], json.keys.sort
    assert_equal @config_path, json["config"]["path"]
    assert_kind_of Hash, json["model"]
    assert_kind_of Array, json["distros"]
    assert_equal [{"repo" => @repo, "name" => "config", "target" => @target},
      {"repo" => @repo, "name" => "codex", "target" => @codex}], json["packages"]
  end

  def test_diff_json_lists_pending_changes_and_keeps_the_exit_status
    json, status = run_json("diff")

    assert_equal 1, status
    refute json["ok"]
    config = json["packages"].find { |p| p["name"] == "config" }
    assert_equal({"repo" => @repo, "name" => "config", "target" => @target, "target_missing" => false,
                  "link" => [".config/app/settings"], "unlink" => [], "conflicts" => []}, config)
    assert_equal [{"dest" => "#{@tmpdir}/etc/test.conf", "reason" => "missing"}], json["system_files"] if linux?
    assert_equal json["pending"], json["packages"].sum { |p| p["link"].size + p["unlink"].size + p["conflicts"].size } +
      json["system_files"].size
  end

  def test_diff_json_reports_conflicts
    FileUtils.mkdir_p(File.join(@target, ".config", "app"))
    File.write(File.join(@target, ".config", "app", "settings"), "mine")

    json, = run_json("diff")

    config = json["packages"].find { |p| p["name"] == "config" }
    assert_equal 1, config["conflicts"].size
    assert_match(/settings/, config["conflicts"].first)
  end

  def test_diff_json_exits_zero_when_nothing_is_pending
    Dotlayer::Stow.new(target: @target).restow(@repo, "config")
    Dotlayer::Stow.new(target: @codex).restow(@repo, "codex")
    File.write(@config_path, File.read(@config_path).sub(/system_files:.*\z/m, ""))

    json, status = run_json("diff")

    assert_equal 0, status
    assert json["ok"]
    assert_equal 0, json["pending"]
  end

  def test_doctor_json
    json, status = run_json("doctor")

    assert_equal %w[checks hints issues ok], json.keys.sort
    assert_equal ["stow installed", "repos exist", "packages exist", "no broken symlinks",
      "managed files are links", "no dangling links into repos"], json["checks"].map { |c| c["name"] }
    assert json["checks"].all? { |c| c.key?("ok") && c["details"].is_a?(Array) }
    assert_equal json["ok"], json["issues"].empty?
    assert_equal(json["ok"] ? 0 : 1, status)
  end

  def test_doctor_json_reports_failed_checks_and_exit_status
    FileUtils.mkdir_p(File.join(@target, ".config", "app"))
    File.write(File.join(@target, ".config", "app", "settings"), "plain file")

    json, status = run_json("doctor")

    check = json["checks"].find { |c| c["name"] == "managed files are links" }
    refute check["ok"]
    assert_match(/settings/, check["details"].first)
    refute json["ok"]
    assert_equal 1, status
  end

  private

  # Returns [parsed JSON, exit status]. Fails if stdout holds anything else.
  def run_json(command)
    status = 0
    out = capture_io do
      Dotlayer::CLI.new.run(["-c", @config_path, "--json", command])
    rescue SystemExit => e
      status = e.status
    end.first

    refute_match(/\e\[/, out)
    [JSON.parse(out), status]
  end

  def linux?
    RbConfig::CONFIG["host_os"].match?(/linux/)
  end
end
