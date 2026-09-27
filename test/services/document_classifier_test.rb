require "test_helper"

class DocumentClassifierTest < ActiveSupport::TestCase
  setup do
    @invoices = categories(:invoices)
    @unsorted = categories(:unsorted)
  end

  test "rule match classifies invoice by filename" do
    document = Document.create!(
      user: users(:admin),
      original_filename: "acme-invoice-42.txt",
      status: "pending",
      source: "web",
      content_type: "text/plain"
    )

    result = DocumentClassifier.new(document, ollama: fake_unavailable_ollama).call(
      text: "Filename: acme-invoice-42.txt\n\nSome body"
    )

    assert_equal @invoices, result.category
    assert_equal "rule", result.classifier_used
    assert result.confidence >= 0.9
  end

  test "keyword fallback classifies resume content" do
    document = Document.create!(
      user: users(:admin),
      original_filename: "profile.txt",
      status: "pending",
      source: "web",
      content_type: "text/plain"
    )

    # Ensure resumes category exists in fixtures or create it
    resumes = Category.find_or_create_by!(slug: "resumes") do |c|
      c.name = "Resumes"
      c.directory_path = "hr/resumes"
      c.keywords = "resume, curriculum vitae, experience, education, skills"
      c.auto_create = true
    end

    result = DocumentClassifier.new(document, ollama: fake_unavailable_ollama).call(
      text: "Curriculum Vitae\nExperience and education and skills"
    )

    assert_equal resumes, result.category
    assert_equal "keywords", result.classifier_used
  end

  test "missing model summary is recovered without losing classification" do
    result, calls = classify_with_responses(nil, { "summary" => "Payment of 42 euros is due Friday." })

    assert_equal "Payment of 42 euros is due Friday.", result.summary
    assert_equal @invoices, result.category
    assert_equal 0.9, result.confidence
    assert_equal 2, calls.length
    assert_equal 192, calls.last[:num_predict]
  end

  test "valid model summary needs no extra request" do
    result, calls = classify_with_responses("  Payment is due Friday.  ")

    assert_equal "Payment is due Friday.", result.summary
    assert_equal 1, calls.length
  end

  test "blank or placeholder summaries fall back to document excerpt after one retry" do
    [ nil, "  ", "Classified by local model", [] ].each do |summary|
      result, calls = classify_with_responses(summary, { "summary" => "" })

      assert_equal "Document excerpt: Payment of 42 euros is due Friday.", result.summary
      assert_equal @invoices, result.category
      assert_equal 2, calls.length
    end
  end

  test "summary request failure preserves successful classification" do
    result, = classify_with_responses(nil, OllamaClient::Unavailable.new("timeout"))

    assert_equal "Document excerpt: Payment of 42 euros is due Friday.", result.summary
    assert_equal @invoices, result.category
    assert_match(/ollama:/, result.classifier_used)
  end

  test "missing readable text is reported honestly" do
    result, = classify_with_responses(nil, {}, text: "Filename: statement.txt\n\n--- Page 1 ---")

    assert_equal "Summary unavailable: no readable document text.", result.summary
  end

  test "unrelated JSON is rejected rather than accepted as a classification" do
    document = Document.new(user: users(:admin), original_filename: "statement.txt")
    client = Object.new
    client.define_singleton_method(:available?) { true }
    client.define_singleton_method(:chat) { |**_| { "@type" => "FAQPage", "mainEntity" => [] } }
    result = DocumentClassifier.new(document, ollama: client).call(text: "Some document content")
    assert_equal "keywords", result.classifier_used
  end

  test "long unicode documents fit context with catalog and instructions included" do
    result, calls = classify_with_responses("A valid summary.", text: "Start " + ("漢字\"\n" * 10000) + " End")
    request = calls.first
    assert_operator request[:system].bytesize + request[:user].bytesize, :<=, OllamaClient.input_byte_budget
    text = JSON.parse(request[:user]).fetch("document_text")
    assert text.start_with?("Start ")
    assert text.end_with?(" End")
    assert_includes request[:schema][:required], "summary"
    assert_includes request[:schema][:properties][:category_slug][:enum], @invoices.slug
  end

  test "issuer category names cannot leak into predictions without source evidence" do
    brand = Category.create!(name: "Deutsche Bahn AG", slug: "issuer-deutsche-bahn-ag",
      directory_path: "issuers/deutsche-bahn", keywords: "Deutsche Bahn AG", user: users(:admin))
    document = Document.new(user: users(:admin), original_filename: "scan.pdf")
    calls = []
    client = Object.new
    client.define_singleton_method(:chat) do |**args|
      calls << args
      { "category_slug" => "invoices", "confidence" => 0.9,
        "summary" => "A power of attorney for tax matters.", "issuer" => "Deutsche Bahn AG", "issuer_confidence" => 1 }
    end
    result = DocumentClassifier.new(document, ollama: client).send(:classify_with_ollama,
      "Vollmacht in Steuersachen", [ @invoices, brand ], { issuer: nil })
    assert_nil result.issuer
    assert_equal 0, result.issuer_confidence
    assert_equal "", result.raw["issuer"]
    refute_includes calls.first[:schema][:properties][:category_slug][:enum], brand.slug
    refute_includes calls.first[:user], "Deutsche Bahn"
  end

  test "source-supported issuer categories remain available" do
    brand = Category.create!(name: "Calumet", slug: "issuer-calumet",
      directory_path: "issuers/calumet", keywords: "Calumet", user: users(:admin))
    document = Document.new(user: users(:admin), original_filename: "scan.pdf")
    client = Object.new
    client.define_singleton_method(:chat) do |**args|
      raise "Brand missing from schema" unless args[:schema][:properties][:category_slug][:enum].include?(brand.slug)
      { "category_slug" => brand.slug, "confidence" => 0.9,
        "summary" => "A purchase receipt.", "issuer" => "Calumet GmbH", "issuer_confidence" => 0.9 }
    end
    result = DocumentClassifier.new(document, ollama: client).send(:classify_with_ollama,
      "Calumet Photo Video receipt", [ @invoices, brand ], { issuer: nil })
    assert_equal "Calumet GmbH", result.issuer
    assert_equal brand, result.category
  end

  private

  def classify_with_responses(summary, recovery = nil, text: "Filename: statement.txt\n\n--- Page 1 ---\nPayment of 42 euros is due Friday.")
    document = Document.new(user: users(:admin), original_filename: "statement.txt", content_type: "text/plain")
    responses = [ { "category_slug" => @invoices.slug, "confidence" => 0.9, "summary" => summary }, recovery ]
    calls = []
    client = Object.new
    client.define_singleton_method(:available?) { true }
    client.define_singleton_method(:chat) do |**args|
      calls << args
      raise "Unexpected extra model request" if responses.empty?
      response = responses.shift
      raise response if response.is_a?(Exception)
      response
    end
    [ DocumentClassifier.new(document, ollama: client).call(text: text), calls ]
  end

  def fake_unavailable_ollama
    client = Object.new
    def client.available? = false
    client
  end
end
