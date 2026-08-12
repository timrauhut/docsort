require "test_helper"

class SessionStoreTest < ActiveSupport::TestCase
  test "uses the configured installer-specific cookie name" do
    assert_equal ENV.fetch("DOCSORT_SESSION_COOKIE", "_docsort_session"),
      Rails.application.config.session_options[:key]
  end
end
