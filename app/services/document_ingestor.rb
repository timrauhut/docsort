# Creates a Document from an uploaded IO (web form or WebDAV).
class DocumentIngestor
  class InvalidUpload < ArgumentError; end
  class UploadTooLarge < InvalidUpload; end

  SUPPORTED_EXTENSIONS = %w[
    .pdf .txt .md .csv .json .xml .html .htm .log .yml .yaml
    .jpg .jpeg .png .webp .tif .tiff .bmp
  ].freeze
  SUPPORTED_MIME_TYPES = %w[
    application/pdf application/json application/xml application/xhtml+xml
  ].freeze

  def initialize(io:, filename:, source:, user:, content_type: nil)
    @io = io
    @filename = File.basename(filename.to_s)
    @source = source
    @user = user
    @content_type = content_type
  end

  def call
    raise InvalidUpload, "filename required" if @filename.blank?
    raise InvalidUpload, "user required" if @user.blank?
    validate_upload!

    @user.ensure_storage!

    document = @user.documents.create!(
      original_filename: @filename,
      title: File.basename(@filename, ".*").tr("_-", " ").squeeze(" ").strip.titleize,
      status: "pending",
      source: @source,
      content_type: @content_type.presence || Marcel::MimeType.for(name: @filename),
      metadata: { ingested_at: Time.current.iso8601 }
    )

    document.file.attach(
      io: rewind_io(@io),
      filename: @filename,
      content_type: document.content_type
    )

    document.update!(
      byte_size: document.file.byte_size,
      content_type: document.file.content_type.presence || document.content_type
    )

    ClassifyDocumentJob.perform_later(document.id) unless document.status == "processing"

    document
  end

  private

  def rewind_io(io)
    io.rewind if io.respond_to?(:rewind)
    io
  end

  def validate_upload!
    extension = File.extname(@filename).downcase
    unless SUPPORTED_EXTENSIONS.include?(extension)
      raise InvalidUpload, "Unsupported file type: #{extension.presence || 'no extension'}"
    end

    detected_type = Marcel::MimeType.for(rewind_io(@io), name: @filename).to_s
    unless detected_type.start_with?("text/", "image/") || SUPPORTED_MIME_TYPES.include?(detected_type)
      raise InvalidUpload, "File contents do not match a supported document type"
    end

    if @io.respond_to?(:size) && @io.size.to_i > Rails.application.config.x.max_upload_bytes
      raise UploadTooLarge, "File exceeds the #{max_upload_megabytes} MB upload limit"
    end
  end

  def max_upload_megabytes
    Rails.application.config.x.max_upload_bytes / 1.megabyte
  end
end
