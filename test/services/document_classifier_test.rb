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

  private

  def fake_unavailable_ollama
    client = Object.new
    def client.available? = false
    client
  end
end
