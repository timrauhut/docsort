require "test_helper"
require "fileutils"
require "open3"
require "tmpdir"

class DocsortInstallerTest < ActiveSupport::TestCase
  setup do
    @tmp = Dir.mktmpdir("docsort-installer-test")
    @bin = File.join(@tmp, "bin")
    FileUtils.mkdir_p(@bin)
    docker = File.join(@bin, "docker")
    File.write(docker, <<~SH)
      #!/bin/sh
      if [ "$1 $2" = "compose version" ]; then exit 0; fi
      if [ "$1" = "compose" ]; then exit 0; fi
      if [ "$1 $2" = "ps --format" ]; then printf '%s\n' "${FAKE_DOCKER_PORTS:-}"; exit 0; fi
      if [ "$1 $2" = "volume inspect" ]; then
        [ "${3:-}" = "${FAKE_EXISTING_VOLUME:-}" ]
        exit $?
      fi
      if [ "$1 $2" = "image inspect" ]; then exit 0; fi
      exit 0
    SH
    FileUtils.chmod(0o755, docker)
  end

  teardown do
    FileUtils.rm_rf(@tmp)
  end

  test "dry run writes isolated project volume and cookie settings" do
    root = File.join(@tmp, "install")
    _out, error, status = run_cli(
      root,
      "--port", "39080",
      "--project-name", "docsort-test",
      "--storage-volume", "docsort_test_storage",
      "--ollama-volume", "docsort_test_ollama",
      "--no-ollama"
    )

    assert status.success?, error
    env = File.read(File.join(root, "docsort.env"))
    assert_includes env, "DOCSORT_PROJECT_NAME=docsort-test"
    assert_includes env, "DOCSORT_STORAGE_VOLUME=docsort_test_storage"
    assert_includes env, "DOCSORT_SESSION_COOKIE=_docsort_test_session"
    assert_includes env, "DOCSORT_FRESH_INSTALL=true"
  end

  test "occupied port is rejected before configuration is written" do
    root = File.join(@tmp, "occupied")
    _out, error, status = run_cli(root, "--port", "39080", extra_env: { "FAKE_DOCKER_PORTS" => "0.0.0.0:39080->80/tcp" })

    refute status.success?
    assert_includes error, "port 39080 is already in use"
    refute_path_exists root
  end

  test "existing storage requires explicit adoption" do
    root = File.join(@tmp, "collision")
    _out, error, status = run_cli(
      root,
      "--port", "39080",
      "--storage-volume", "existing_storage",
      extra_env: { "FAKE_EXISTING_VOLUME" => "existing_storage" }
    )

    refute status.success?
    assert_includes error, "explicitly use --adopt-existing-volume"
    refute_path_exists root
  end

  private

  def run_cli(root, *arguments, extra_env: {})
    env = {
      "PATH" => "#{@bin}:#{ENV.fetch("PATH")}",
      "DOCSORT_INSTALL_ROOT" => root,
      "DOCSORT_DRY_RUN" => "true"
    }.merge(extra_env)
    Open3.capture3(env, Rails.root.join("packaging/docsort").to_s, "install", "--lan", *arguments)
  end
end
