require "test_helper"

class SecureTransportTest < ActionDispatch::IntegrationTest
  test "responses include a restrictive content security policy" do
    get login_path

    assert_response :success
    assert_includes response.headers["Content-Security-Policy"], "default-src 'self'"
    assert_includes response.headers["Content-Security-Policy"], "object-src 'none'"
  end

  test "does not expose Active Storage direct upload or blob routes" do
    post "/rails/active_storage/direct_uploads"
    assert_response :not_found

    get "/rails/active_storage/blobs/redirect/not-a-real-id/file.pdf"
    assert_response :not_found
  end

  test "refuses login over insecure transport when production protection is enabled" do
    previous = Rails.application.config.x.allow_insecure_auth
    Rails.application.config.x.allow_insecure_auth = false

    post login_path, params: { username: "alice", password: "password123" }

    assert_response :upgrade_required
    assert_equal "TLS/1.2, HTTP/1.1", response.headers["Upgrade"]
  ensure
    Rails.application.config.x.allow_insecure_auth = previous
  end
end
