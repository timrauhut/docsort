require "test_helper"

class TextExtractorTest < ActiveSupport::TestCase
  setup do
    @extractor = TextExtractor.new(
      Document.new(original_filename: "doc.pdf", status: "pending", source: "web")
    )
  end

  test "format_pages labels every page with no artificial 20-page cap" do
    pages = Array.new(25) { |i| "Content of page #{i + 1} with enough letters" }
    text = @extractor.send(:format_pages, pages)

    assert_includes text, "--- Page 1 ---"
    assert_includes text, "--- Page 25 ---"
    assert_includes text, "Content of page 25"
    assert_equal 25, text.scan(/--- Page \d+ ---/).size
  end

  test "format_pages skips blank pages" do
    text = @extractor.send(:format_pages, [ "Hello world page", "", "Third" ])
    assert_includes text, "--- Page 1 ---"
    assert_includes text, "--- Page 3 ---"
    refute_includes text, "--- Page 2 ---"
  end

  test "sparse page detection" do
    assert @extractor.send(:sparse_page?, ".... ---")
    assert @extractor.send(:sparse_page?, "ab")
    refute @extractor.send(:sparse_page?, "This page has a real paragraph of words for classification")
  end

  test "pick_richer prefers OCR when it has more content" do
    chosen = @extractor.send(
      :pick_richer,
      ".",
      "Scanned invoice total amount due in Euro today"
    )
    assert_includes chosen, "Scanned invoice"
  end

  test "text for model keeps head and tail of long extracts" do
    classifier = DocumentClassifier.new(
      Document.new(original_filename: "x.pdf", status: "pending", source: "web"),
      ollama: Object.new
    )
    long = "A" * 8_000 + "MIDDLE_MARKER" + "B" * 8_000
    # Force small limit via method behavior: length > 12000 default
    sample = classifier.send(:text_for_model, long)
    assert sample.length <= 12_000 + 20
    assert_includes sample, "[...]"
    assert sample.start_with?("A")
    assert sample.end_with?("B")
  end
end
