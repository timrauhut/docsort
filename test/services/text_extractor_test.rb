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

  test "ocr enrich skips tesseract when every page has a text layer" do
    pages = [
      "Invoice number 12345 with enough embedded text",
      "Second page also has a full paragraph of content"
    ]
    called = false
    @extractor.define_singleton_method(:ocr_pdf_page) do |*_args|
      called = true
      "should not run"
    end
    @extractor.define_singleton_method(:pdf_page_count) { |_path| 2 }
    @extractor.define_singleton_method(:ocr_all_pages?) { false }

    result = @extractor.send(:ocr_enrich_pdf_pages, "/tmp/x.pdf", pages)

    assert_equal pages, result
    refute called, "Tesseract must not run when embedded text is usable"
  end

  test "ocr enrich falls back for sparse pages only" do
    pages = [ "Full embedded text layer on page one with many words", "" ]
    @extractor.define_singleton_method(:pdf_page_count) { |_path| 2 }
    @extractor.define_singleton_method(:ocr_all_pages?) { false }
    @extractor.define_singleton_method(:ocr_pdf_page) do |_path, page_num|
      "OCR text for page #{page_num} with scanned content"
    end

    result = @extractor.send(:ocr_enrich_pdf_pages, "/tmp/x.pdf", pages)

    assert_equal pages[0], result[0]
    assert_includes result[1], "OCR text for page 2"
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
