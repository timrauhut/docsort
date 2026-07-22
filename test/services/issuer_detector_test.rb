require "test_helper"

class IssuerDetectorTest < ActiveSupport::TestCase
  test "detects company with legal suffix" do
    document = Document.new(original_filename: "letter.txt", source: "web", status: "pending")
    text = <<~TXT
      Acme Industries GmbH
      Customer service

      Dear customer,

      Your invoice is attached.

      www.acme-industries.example
    TXT

    result = IssuerDetector.new(document, text: text).call
    assert_includes result[:issuer].to_s, "Acme"
    assert result[:confidence] > 0.3
  end

  test "detects from-line sender" do
    document = Document.new(original_filename: "note.txt", source: "web", status: "pending")
    text = "From: Stadtwerke München\n\nYour yearly statement."

    result = IssuerDetector.new(document, text: text).call
    assert_match(/Stadtwerke|München/i, result[:issuer].to_s)
  end
end
