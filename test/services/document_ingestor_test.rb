require "test_helper"

class DocumentIngestorTest < ActiveSupport::TestCase
  test "rejects unsupported extensions" do
    error = assert_raises(DocumentIngestor::InvalidUpload) do
      DocumentIngestor.new(
        io: StringIO.new("binary"),
        filename: "payload.exe",
        source: "web",
        user: users(:alice)
      ).call
    end

    assert_match(/Unsupported file type/, error.message)
  end

  test "rejects files over the configured limit" do
    previous = Rails.application.config.x.max_upload_bytes
    Rails.application.config.x.max_upload_bytes = 4

    assert_raises(DocumentIngestor::InvalidUpload) do
      DocumentIngestor.new(
        io: StringIO.new("too large"),
        filename: "notes.txt",
        source: "web",
        user: users(:alice)
      ).call
    end
  ensure
    Rails.application.config.x.max_upload_bytes = previous
  end
end
