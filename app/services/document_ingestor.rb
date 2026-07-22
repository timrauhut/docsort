# Creates a Document from an uploaded IO (web form or WebDAV).
class DocumentIngestor
  def initialize(io:, filename:, source:, content_type: nil)
    @io = io
    @filename = File.basename(filename.to_s)
    @source = source
    @content_type = content_type
  end

  def call
    raise ArgumentError, "filename required" if @filename.blank?

    document = Document.create!(
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

    # after_create_commit only fires once; if attach happens after create, enqueue now
    ClassifyDocumentJob.perform_later(document.id) unless document.status == "processing"

    document
  end

  private

  def rewind_io(io)
    io.rewind if io.respond_to?(:rewind)
    io
  end
end
