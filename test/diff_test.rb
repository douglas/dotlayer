require "test_helper"

class DiffTest < Minitest::Test
  include TestConfigHelper

  def setup
    @tmpdir = Dir.mktmpdir
    @target = File.join(@tmpdir, "home")
    @repo = File.join(@tmpdir, "repo")
    FileUtils.mkdir_p([@target, File.join(@repo, "config", ".config", "test")])
    File.write(File.join(@repo, "config", ".config", "test", "config.yml"), "hello")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_reports_links_without_changing_anything
    result, output = run_diff

    refute result
    assert_match(/LINK\S*\s+\.config\/test\/config\.yml/, output)
    assert_match(/1 change\(s\) pending/, output)
    assert_empty Dir.children(@target)
  end

  def test_no_changes_after_install
    install

    result, output = run_diff

    assert result
    assert_match(/No changes pending/, output)
    refute_match(/LINK/, output)
  end

  def test_reports_conflicts
    FileUtils.mkdir_p(File.join(@target, ".config", "test"))
    File.write(File.join(@target, ".config", "test", "config.yml"), "mine")

    result, output = run_diff

    refute result
    assert_match(/CONFLICT\S*\s+.*\.config\/test\/config\.yml/, output)
    assert_match(/1 change\(s\) pending/, output)
    assert_equal "mine", File.read(File.join(@target, ".config", "test", "config.yml"))
  end

  def test_reports_stale_links_as_unlink
    install
    stale = File.join(@target, ".config", "test", "old.yml")
    File.symlink("../../../repo/config/.config/test/gone.yml", stale)

    result, output = run_diff

    refute result
    assert_match(/UNLINK\S*\s+\.config\/test\/old\.yml/, output)
    assert File.symlink?(stale)
  end

  def test_system_files_content_mode_and_missing
    etc = File.join(@repo, ".system")
    FileUtils.mkdir_p(etc)
    names = %w[same diff mode absent]
    dests = names.to_h { |n| [n, File.join(@tmpdir, "#{n}.conf")] }
    {"same" => "a", "diff" => "new", "mode" => "m", "absent" => "z"}.each do |n, body|
      File.write(File.join(etc, "#{n}.conf"), body)
    end
    {"same" => "a", "diff" => "old", "mode" => "m"}.each { |n, body| File.write(dests[n], body) }
    %w[same diff].each { |n| File.chmod(0o644, dests[n]) }
    File.chmod(0o600, dests["mode"])
    entries = names.map { |n| {"source" => ".system/#{n}.conf", "dest" => dests[n]} }

    result, output = run_diff(system_files: entries)

    refute result
    refute_match(/same\.conf/, output)
    assert_match(/diff\.conf \(content differs\)/, output)
    assert_match(/mode\.conf \(mode 0600, want 0644\)/, output)
    assert_match(/absent\.conf \(missing\)/, output)
  end

  def test_unreadable_system_file_is_reported
    skip "root can read anything" if Process.uid.zero?
    FileUtils.mkdir_p(File.join(@repo, ".system"))
    File.write(File.join(@repo, ".system", "s.conf"), "a")
    dest = File.join(@tmpdir, "s.conf")
    File.write(dest, "a")
    File.chmod(0o000, dest)

    _, output = run_diff(system_files: [{"source" => ".system/s.conf", "dest" => dest}])

    assert_match(/s\.conf \(unreadable, cannot compare\)/, output)
  end

  def test_cli_exits_1_when_changes_pending
    config_path = File.join(@tmpdir, "dotlayer.yml")
    File.write(config_path, "target: #{@target}\nrepos:\n  - path: #{@repo}\npackages:\n  - config\n")

    error = assert_raises(SystemExit) {
      capture_io { Dotlayer::CLI.new.run(["-c", config_path, "diff"]) }
    }

    assert_equal 1, error.status
  end

  private

  def build_config(**overrides)
    stub_config(target: @target, repos: [build_repo(path: @repo)], packages: %w[config], **overrides)
  end

  def install
    capture_io { Dotlayer::Commands::Install.new(config: build_config, detector: stub_detector).run }
  end

  def run_diff(**overrides)
    result = nil
    output = capture_io {
      result = Dotlayer::Commands::Diff.new(config: build_config(**overrides), detector: stub_detector).run
    }.first
    [result, output]
  end
end
