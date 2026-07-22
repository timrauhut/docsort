# Extracts plain text from uploaded documents for classification.
class TextExtractor
  MAX_CHARS = 12_000

  def initialize(document)
    @document = document
  end

  def call
    return "" unless @document.file.attached?

    blob = @document.file.blob
    content_type = blob.content_type.to_s
    filename = @document.original_filename.to_s

    text =
      if content_type.include?("pdf") || filename.downcase.end_with?(".pdf")
        extract_pdf(blob)
      elsif text_like?(content_type, filename)
        extract_plain(blob)
      else
        # Binary / unknown: use filename + metadata only
        ""
      end

    # Always include filename cues for the classifier
    parts = [ "Filename: #{filename}", text.to_s.strip ].reject(&:blank?)
    parts.join("\n\n").truncate(MAX_CHARS)
  end

  private

  def text_like?(content_type, filename)
    return true if content_type.start_with?("text/")
    return true if content_type.in?(%w[application/json application/xml application/javascript])

    filename.downcase.match?(/\.(txt|md|markdown|csv|json|xml|html|htm|log|yml|yaml|rb|py|js|ts|css)$/)
  end

  def extract_plain(blob)
    blob.open do |file|
      file.read.force_encoding("UTF-8").scrub
    end
  rescue StandardError => e
    Rails.logger.warn("TextExtractor plain failed: #{e.message}")
    ""
  end

  def extract_pdf(blob)
    require "pdf-reader"

    blob.open do |file|
      reader = PDF::Reader.new(file.path)
      reader.pages.first(20).map { |page| page.text.to_s }.join("\n\n")
    end
  rescue StandardError => e
    Rails.logger.warn("TextExtractor PDF failed: #{e.message}")
    ""
  end
end
