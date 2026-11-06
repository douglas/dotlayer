require "test_helper"

class DoctorTest < Minitest::Test
  include TestConfigHelper

  def test_reports_missing_repo
    config = stub_config(target: "/nonexistent/home", repos: [build_repo(path: "/nonexistent/repo")])

    output = capture_io {
      Dotlayer::Commands::Doctor.new(config:, detector: stub_detector).run
    }.first

    assert_match(/missing/, output)
    assert_match(/1 issue/, output)
  end

  def test_detects_broken_symlinks
    tmpdir = Dir.mktmpdir
    target = File.join(tmpdir, "home")
    repo = File.join(tmpdir, "repo")
    FileUtils.mkdir_p([File.join(target, ".config"), File.join(repo, "config", ".config")])
    FileUtils.touch(File.join(repo, "config", ".config", "broken_link_target"))

    File.symlink("/nonexistent/path", File.join(target, ".config", "broken_link_target"))

    config = stub_config(target: target, repos: [build_repo(path: repo)], packages: %w[config])

    output = capture_io {
      Dotlayer::Commands::Doctor.new(config:, detector: stub_detector).run
    }.first

    assert_match(/Broken symlink/, output)
  ensure
    FileUtils.rm_rf(tmpdir)
  end

  def test_ignores_broken_symlinks_outside_managed_config_paths
    tmpdir = Dir.mktmpdir
    target = File.join(tmpdir, "home")
    repo = File.join(tmpdir, "repo")
    FileUtils.mkdir_p([
      File.join(target, ".config"),
      File.join(target, ".local", "share", "Steam"),
      File.join(target, "work"),
      File.join(repo, "config", ".config"),
      File.join(repo, "config", ".local", "bin"),
      File.join(repo, "config", "work")
    ])

    FileUtils.touch(File.join(repo, "config", ".local", "bin", "managed-tool"))
    File.symlink("/nonexistent/path", File.join(target, ".local", "share", "Steam", "stale"))
    File.symlink("/nonexistent/path", File.join(target, "work", "stale"))

    config = stub_config(target: target, repos: [build_repo(path: repo)], packages: %w[config])

    output = capture_io {
      Dotlayer::Commands::Doctor.new(config:, detector: stub_detector).run
    }.first

    assert_match(/No issues found/, output)
    refute_match(/Steam\/stale/, output)
    refute_match(/work\/stale/, output)
  ensure
    FileUtils.rm_rf(tmpdir)
  end

  def test_reports_dangling_links_into_repo_anywhere_under_target
    with_scan_fixture do |target, repo, config|
      output = run_doctor(config)

      assert_match(/1 found/, output)
      assert_match(%r{Dangling link into repo: #{target}/projects/a/dangling -> #{repo}/config/gone}, output)
      assert_match(%r{rm #{target}/projects/a/dangling}, output)
      refute_match(/valid/, output)
      refute_match(/outside/, output)
      refute_match(/via_symlinked_dir/, output)
      refute_match(/state_backup/, output)
      refute_match(/cache_stale/, output)
      assert_match(/1 issue/, output)
    end
  end

  def test_reports_managed_file_replaced_by_plain_file
    Dir.mktmpdir do |tmpdir|
      target = File.join(tmpdir, "home")
      repo = File.join(tmpdir, "repo")
      FileUtils.mkdir_p([File.join(repo, "config", ".config", "app"), File.join(target, ".config", "app")])
      File.write(File.join(repo, "config", ".config", "app", "settings"), "repo\n")
      File.write(File.join(target, ".config", "app", "settings"), "rewritten by the app\n")
      config = stub_config(target:, repos: [build_repo(path: repo)], packages: %w[config])

      output = run_doctor(config)

      assert_match(/1 not linked/, output)
      assert_match(%r{repo/config: .*\.config/app/settings}, output)
      assert_match(/dotlayer install/, output)
    end
  end

  def test_notes_when_global_ignore_is_not_linked_yet
    Dir.mktmpdir do |tmpdir|
      target = File.join(tmpdir, "home")
      repo = File.join(tmpdir, "repo")
      FileUtils.mkdir_p([File.join(repo, "stow"), File.join(repo, "config", ".config", "app"), target])
      File.write(File.join(repo, "stow", ".stow-global-ignore"), "\\.git\n")
      File.write(File.join(repo, "config", ".config", "app", "settings"), "repo\n")
      config = stub_config(target:, repos: [build_repo(path: repo)], packages: %w[stow config])
      original_home = ENV["HOME"]
      ENV["HOME"] = target

      output = run_doctor(config)

      assert_match(/Note: .*stow-global-ignore.*not linked yet/, output)
    ensure
      ENV["HOME"] = original_home
    end
  end

  def test_package_target_is_checked_for_plain_files_broken_links_and_dangling_links
    Dir.mktmpdir do |tmpdir|
      target = File.join(tmpdir, "home")
      codex = File.join(tmpdir, "codex-home")
      repo = File.join(tmpdir, "repo")
      FileUtils.mkdir_p([File.join(repo, "codex", ".config"), target, codex])
      File.write(File.join(repo, "codex", "config.toml"), "repo\n")
      File.write(File.join(codex, "config.toml"), "rewritten\n")
      File.symlink(File.join(repo, "codex", "gone"), File.join(codex, "dangling"))
      config = stub_config(
        target:, repos: [build_repo(path: repo, packages: %w[codex], targets: {"codex" => codex})]
      )

      output = run_doctor(config)

      assert_match(%r{repo/codex: .*config\.toml}, output)
      assert_match(/Dangling link into repo: #{Regexp.escape(File.join(codex, "dangling"))}/, output)
    end
  end

  def test_linked_install_passes_link_check
    Dir.mktmpdir do |tmpdir|
      target = File.join(tmpdir, "home")
      repo = File.join(tmpdir, "repo")
      FileUtils.mkdir_p([File.join(repo, "config", ".config", "app"), target])
      File.write(File.join(repo, "config", ".config", "app", "settings"), "repo\n")
      Dotlayer::Stow.new(target:).restow(repo, "config")
      config = stub_config(target:, repos: [build_repo(path: repo)], packages: %w[config])

      output = run_doctor(config)

      assert_match(/still links\.\.\. .*yes/, output)
      assert_match(/No issues found/, output)
    end
  end

  def test_dangling_scan_enters_checkouts_a_package_ships_into_under_its_own_target
    Dir.mktmpdir do |tmpdir|
      target = File.join(tmpdir, "home")
      codex = File.join(tmpdir, "codex-home")
      repo = File.join(tmpdir, "repo")
      FileUtils.mkdir_p([File.join(repo, "codex", "shipped"), File.join(codex, "shipped", ".git"), File.join(codex, "other", ".git"), target])
      gone = File.join(repo, "codex", "gone")
      File.symlink(gone, File.join(codex, "shipped", "dangling"))
      File.symlink(gone, File.join(codex, "other", "dangling"))
      config = stub_config(target:, repos: [build_repo(path: repo, packages: %w[codex], targets: {"codex" => codex})])

      output = run_doctor(config)

      assert_match(%r{Dangling link into repo: .*shipped/dangling}, output)
      refute_match(%r{other/dangling}, output)
    end
  end

  def test_dangling_scan_skips_other_git_checkouts
    with_scan_fixture do |target, repo, config|
      checkout = File.join(target, "src", "project")
      FileUtils.mkdir_p(File.join(checkout, ".git"))
      File.symlink(File.join(repo, "config", "gone"), File.join(checkout, "in_checkout"))

      output = run_doctor(config)

      refute_match(/in_checkout/, output)
      assert_match(/1 found/, output)
    end
  end

  def test_dangling_scan_enters_checkouts_a_package_ships_into
    with_scan_fixture do |target, repo, config|
      checkout = File.join(target, "work", "app")
      FileUtils.mkdir_p([File.join(checkout, ".git"), File.join(repo, "config", "work", "app")])
      File.symlink(File.join(repo, "config", "work", "app", "gone.yml"), File.join(checkout, "shipped_stale"))

      output = run_doctor(config)

      assert_match(%r{Dangling link into repo: #{checkout}/shipped_stale}, output)
    end
  end

  def test_dangling_scan_respects_max_depth
    with_scan_fixture do |_target, _repo, config|
      output = run_doctor(config, max_depth: 1)

      assert_match(/No issues found/, output)
    end
  end

  def test_doctor_returns_false_when_issues_found
    with_scan_fixture do |_target, _repo, config|
      result = nil
      capture_io { result = Dotlayer::Commands::Doctor.new(config:, detector: stub_detector).run }

      refute result
    end
  end

  def test_doctor_returns_true_when_healthy
    Dir.mktmpdir do |tmpdir|
      repo = File.join(tmpdir, "repo")
      FileUtils.mkdir_p(File.join(repo, "config"))
      config = stub_config(target: tmpdir, repos: [build_repo(path: repo)], packages: %w[config])
      result = nil
      capture_io { result = Dotlayer::Commands::Doctor.new(config:, detector: stub_detector).run }

      assert result
    end
  end

  def test_stow_missing_reports_issue
    tmpdir = Dir.mktmpdir
    repo = File.join(tmpdir, "repo")
    FileUtils.mkdir_p(File.join(repo, "config"))

    config = stub_config(target: tmpdir, repos: [build_repo(path: repo)], packages: %w[config])

    original_path = ENV["PATH"]
    ENV["PATH"] = ""
    output = capture_io {
      Dotlayer::Commands::Doctor.new(config:, detector: stub_detector).run
    }.first
    ENV["PATH"] = original_path

    assert_match(/missing/, output)
    assert_match(/Stow is not installed/, output)
  ensure
    ENV["PATH"] = original_path
    FileUtils.rm_rf(tmpdir)
  end

  def test_missing_package_directory_reports_issue
    tmpdir = Dir.mktmpdir
    repo = File.join(tmpdir, "repo")
    FileUtils.mkdir_p(repo)

    config = stub_config(target: tmpdir, repos: [build_repo(path: repo)], packages: %w[config])

    # Stub Resolver to return a package whose directory doesn't exist
    fake_resolver = Object.new
    fake_resolver.define_singleton_method(:resolve) { [[repo, "nonexistent-pkg"]] }

    doctor = Dotlayer::Commands::Doctor.new(config:, detector: stub_detector)
    original_new = Dotlayer::Resolver.method(:new)
    Dotlayer::Resolver.define_singleton_method(:new) { |**_| fake_resolver }

    output = capture_io { doctor.run }.first

    assert_match(/Package directory missing/, output)
  ensure
    Dotlayer::Resolver.define_singleton_method(:new, original_new) if original_new
    FileUtils.rm_rf(tmpdir)
  end

  def test_multiple_issues_reports_count
    config = stub_config(
      target: "/nonexistent/home",
      repos: [build_repo(path: "/nonexistent/repo1"), build_repo(path: "/nonexistent/repo2")]
    )

    output = capture_io {
      Dotlayer::Commands::Doctor.new(config:, detector: stub_detector).run
    }.first

    assert_match(/2 issue/, output)
  end

  def test_no_issues_when_healthy
    tmpdir = Dir.mktmpdir
    repo = File.join(tmpdir, "repo")
    FileUtils.mkdir_p(File.join(repo, "config"))

    config = stub_config(target: tmpdir, repos: [build_repo(path: repo)], packages: %w[config])

    output = capture_io {
      Dotlayer::Commands::Doctor.new(config:, detector: stub_detector).run
    }.first

    assert_match(/No issues found/, output)
  ensure
    FileUtils.rm_rf(tmpdir)
  end

  private

  def run_doctor(config, **options)
    capture_io {
      Dotlayer::Commands::Doctor.new(config:, detector: stub_detector, **options).run
    }.first
  end

  def with_scan_fixture
    Dir.mktmpdir do |tmpdir|
      target = File.join(tmpdir, "home")
      repo = File.join(tmpdir, "repo")
      elsewhere = File.join(tmpdir, "elsewhere")
      FileUtils.mkdir_p([
        File.join(target, "projects", "a"), File.join(target, ".cache"),
        File.join(target, ".local", "state", "app", "backups"),
        File.join(repo, "config"), elsewhere
      ])
      FileUtils.touch(File.join(repo, "config", "real"))

      File.symlink(File.join(repo, "config", "real"), File.join(target, "valid"))
      File.symlink(File.join(repo, "config", "gone"), File.join(target, "projects", "a", "dangling"))
      File.symlink("/nonexistent/outside", File.join(target, "outside"))
      File.symlink(File.join(repo, "config", "gone"), File.join(target, ".cache", "cache_stale"))
      File.symlink(File.join(repo, "config", "gone"), File.join(target, ".local", "state", "app", "backups", "state_backup"))
      File.symlink(File.join(repo, "config", "gone"), File.join(elsewhere, "via_symlinked_dir"))
      File.symlink(elsewhere, File.join(target, "linkdir"))

      config = stub_config(target:, repos: [build_repo(path: repo)], packages: %w[config])
      yield target, repo, config
    end
  end
end
