# Extracts plain text from uploaded documents for classification.
# PDFs: embedded text on every page, plus OCR (Tesseract) for pages that
# lack a usable text layer (scanned / image-only). Images can be OCR'd too.
class TextExtractor
  # Stored / search corpus — keep multi-page OCR, not just a short snippet.
  MAX_CHARS = ENV.fetch("DOCSORT_EXTRACT_MAX_CHARS", "100000").to_i
  # A page with fewer than this many letters/digits is treated as needing OCR.
  SPARSE_PAGE_CHARS = ENV.fetch("DOCSORT_OCR_SPARSE_CHARS", "40").to_i
  OCR_DPI = ENV.fetch("DOCSORT_OCR_DPI", "200").to_i
  OCR_TIMEOUT = ENV.fetch("DOCSORT_OCR_TIMEOUT", "120").to_i
  # all = OCR every page (merge with embedded text); auto = sparse pages only; off = never
  OCR_MODE = ENV.fetch("DOCSORT_OCR_MODE", "all").to_s.downcase
  OCR_LANGS = ENV.fetch("DOCSORT_OCR_LANGS", "eng+deu").to_s

  def initialize(document)
    @document = document
  end

  def call
    return "" unless @document.file.attached?

    blob = @document.file.blob
    content_type = blob.content_type.to_s
    filename = @document.original_filename.to_s

    text =
      if pdf?(content_type, filename)
        extract_pdf(blob)
      elsif image?(content_type, filename)
        extract_image_ocr(blob)
      elsif text_like?(content_type, filename)
        extract_plain(blob)
      else
        ""
      end

    parts = [ "Filename: #{filename}", text.to_s.strip ].reject(&:blank?)
    parts.join("\n\n").truncate(MAX_CHARS)
  end

  def self.ocr_available?
    system("which", "tesseract", out: File::NULL, err: File::NULL) &&
      system("which", "pdftoppm", out: File::NULL, err: File::NULL)
  end

  def self.tesseract_available?
    system("which", "tesseract", out: File::NULL, err: File::NULL)
  end

  private

  def pdf?(content_type, filename)
    content_type.include?("pdf") || filename.downcase.end_with?(".pdf")
  end

  def image?(content_type, filename)
    content_type.start_with?("image/") ||
      filename.downcase.match?(/\.(png|jpe?g|tiff?|webp|bmp|gif)$/)
  end

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

  def extract_image_ocr(blob)
    return "" unless self.class.tesseract_available?
    return "" if ocr_disabled?

    blob.open do |file|
      ocr_image(file.path)
    end
  rescue StandardError => e
    Rails.logger.warn("TextExtractor image OCR failed: #{e.message}")
    ""
  end

  def extract_pdf(blob)
    blob.open do |file|
      path = file.path
      pages = embedded_pdf_pages(path)

      if ocr_enabled? && self.class.ocr_available?
        pages = ocr_enrich_pdf_pages(path, pages)
      elsif pages.empty?
        Rails.logger.warn("TextExtractor: no embedded PDF text and OCR unavailable")
      end

      format_pages(pages)
    end
  rescue StandardError => e
    Rails.logger.warn("TextExtractor PDF failed: #{e.message}")
    ""
  end

  def embedded_pdf_pages(path)
    require "pdf-reader"

    reader = PDF::Reader.new(path)
    reader.pages.map { |page| page.text.to_s.force_encoding("UTF-8").scrub.strip }
  rescue StandardError => e
    Rails.logger.warn("TextExtractor pdf-reader failed: #{e.message}")
    []
  end

  # Ensure we have one entry per page and OCR sparse (or all) pages.
  def ocr_enrich_pdf_pages(path, embedded_pages)
    page_count = [ embedded_pages.size, pdf_page_count(path) ].max
    page_count = 1 if page_count < 1

    Array.new(page_count) do |index|
      page_num = index + 1
      embedded = embedded_pages[index].to_s
      needs_ocr = ocr_all_pages? || sparse_page?(embedded)

      if needs_ocr
        ocr_text = ocr_pdf_page(path, page_num)
        # Prefer the richer of embedded vs OCR so we never lose a good text layer.
        pick_richer(embedded, ocr_text)
      else
        embedded
      end
    end
  end

  def pdf_page_count(path)
    require "pdf-reader"
    PDF::Reader.new(path).page_count
  rescue StandardError
    0
  end

  def ocr_pdf_page(path, page_num)
    Dir.mktmpdir("docsort-ocr") do |dir|
      prefix = File.join(dir, "page")
      # Render a single page to PNG
      ok = system(
        "pdftoppm",
        "-f", page_num.to_s,
        "-l", page_num.to_s,
        "-png",
        "-r", OCR_DPI.to_s,
        "-singlefile",
        path,
        prefix,
        out: File::NULL,
        err: File::NULL
      )
      unless ok
        Rails.logger.warn("TextExtractor pdftoppm failed for page #{page_num}")
        return ""
      end

      image = "#{prefix}.png"
      return "" unless File.exist?(image)

      ocr_image(image)
    end
  rescue StandardError => e
    Rails.logger.warn("TextExtractor OCR page #{page_num} failed: #{e.message}")
    ""
  end

  def ocr_image(image_path)
    require "open3"

    cmd = [
      "tesseract",
      image_path,
      "stdout",
      "-l", OCR_LANGS,
      "--psm", "3"
    ]

    stdout, stderr, status = Open3.capture3(*cmd)
    unless status.success?
      Rails.logger.warn("TextExtractor tesseract failed: #{stderr.to_s.truncate(200)}")
      return ""
    end

    stdout.to_s.force_encoding("UTF-8").scrub.strip
  end

  def sparse_page?(text)
    significant_chars(text) < SPARSE_PAGE_CHARS
  end

  def significant_chars(text)
    text.to_s.gsub(/[^\p{L}\p{N}]/u, "").length
  end

  def pick_richer(a, b)
    significant_chars(b) > significant_chars(a) ? b.to_s : a.to_s
  end

  def format_pages(pages)
    pages.each_with_index.filter_map do |text, index|
      body = text.to_s.strip
      next if body.blank?

      "--- Page #{index + 1} ---\n#{body}"
    end.join("\n\n")
  end

  def ocr_disabled?
    OCR_MODE.in?(%w[off false no 0])
  end

  def ocr_enabled?
    !ocr_disabled?
  end

  def ocr_all_pages?
    OCR_MODE.in?(%w[all always force true])
  end
end
