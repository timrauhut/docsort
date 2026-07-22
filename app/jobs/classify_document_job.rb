class ClassifyDocumentJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(document_id)
    document = Document.find(document_id)
    return if document.status == "processing"

    document.update!(status: "processing", error_message: nil)

    text = TextExtractor.new(document).call
    document.update!(extracted_text: text.presence)

    result = DocumentClassifier.new(document).call(text: text)

    document.issuer = result.issuer
    document.issuer_confidence = result.issuer_confidence

    if result.category
      document.category = result.category
      document.confidence = result.confidence
      document.summary = result.summary
      document.tag_list = result.tags
      document.classifier_used = result.classifier_used
      document.classified_at = Time.current
      document.metadata = (document.metadata || {}).merge(
        "classification" => result.raw,
        "classifier" => result.classifier_used,
        "issuer" => result.issuer,
        "issuer_confidence" => result.issuer_confidence
      )
      document.status = "classified"
      document.save!

      DocumentOrganizer.new(document).call
    else
      document.update!(
        status: "unsorted",
        summary: result.summary,
        classifier_used: result.classifier_used,
        classified_at: Time.current,
        metadata: (document.metadata || {}).merge(
          "issuer" => result.issuer,
          "issuer_confidence" => result.issuer_confidence
        )
      )
    end
  rescue StandardError => e
    Rails.logger.error("ClassifyDocumentJob failed for ##{document_id}: #{e.class} #{e.message}")
    document&.update(status: "failed", error_message: e.message)
    raise
  end
end
