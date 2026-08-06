require "test_helper"

class WebdavControllerTest < ActionDispatch::IntegrationTest
  setup do
    @previous_inbox_root = Rails.application.config.x.inbox_root
    @previous_allow_insecure = Rails.application.config.x.webdav.allow_insecure
    @inbox_root = Pathname.new(Dir.mktmpdir("docsort-webdav"))
    Rails.application.config.x.inbox_root = @inbox_root.to_s
  end

  teardown do
    Rails.application.config.x.inbox_root = @previous_inbox_root
    Rails.application.config.x.webdav.allow_insecure = @previous_allow_insecure
    FileUtils.rm_rf(@inbox_root)
  end

  test "refuses credentials over insecure production-style transport" do
    Rails.application.config.x.webdav.allow_insecure = false

    get "/webdav", headers: authorization_header

    assert_response :upgrade_required
  end

  test "escapes filenames in directory HTML" do
    Rails.application.config.x.webdav.allow_insecure = true
    users(:alice).ensure_storage!
    File.write(Pathname.new(users(:alice).inbox_root).join(%(quote" file.txt)), "safe")

    get "/webdav", headers: authorization_header

    assert_response :success
    assert_includes response.body, "quote%22%20file.txt"
    refute_includes response.body, %(href="/webdav/quote" file.txt")
  end

  private

  def authorization_header
    credentials = ActionController::HttpAuthentication::Basic.encode_credentials("alice", "password123")
    { "Authorization" => credentials }
  end
end
