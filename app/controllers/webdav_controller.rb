# Minimal WebDAV endpoint for drag-and-drop / Finder / curl uploads.
# Uploads land as Documents and are classified + sorted automatically.
class WebdavController < ApplicationController
  include ActionController::HttpAuthentication::Basic::ControllerMethods

  skip_before_action :verify_authenticity_token, raise: false
  before_action :authenticate
  before_action :set_paths

  def handle
    case request.method
    when "OPTIONS" then handle_options
    when "GET", "HEAD" then handle_get
    when "PUT" then handle_put
    when "DELETE" then handle_delete
    when "MKCOL" then handle_mkcol
    when "PROPFIND" then handle_propfind
    when "PROPPATCH" then head :ok
    when "COPY" then handle_copy
    when "MOVE" then handle_move
    else
      head :method_not_allowed
    end
  end

  private

  def authenticate
    authenticate_or_request_with_http_basic("DocSort WebDAV") do |username, password|
      expected_user = Rails.application.config.x.webdav.username
      expected_pass = Rails.application.config.x.webdav.password
      secure_equals?(username, expected_user) && secure_equals?(password, expected_pass)
    end
  end

  def secure_equals?(actual, expected)
    ActiveSupport::SecurityUtils.secure_compare(
      Digest::SHA256.hexdigest(actual.to_s),
      Digest::SHA256.hexdigest(expected.to_s)
    )
  end



  def set_paths
    relative = params[:path].to_s
    @upload_root = Pathname.new(Rails.application.config.x.inbox_root)
    FileUtils.mkdir_p(@upload_root)

    candidate = @upload_root.join(relative).cleanpath
    unless candidate.to_s.start_with?(@upload_root.to_s)
      head :bad_request
      return
    end
    @file_path = candidate
    @relative = relative
  end

  def handle_options
    response.headers["Allow"] = "GET,HEAD,PUT,DELETE,MKCOL,PROPFIND,PROPPATCH,COPY,MOVE,OPTIONS"
    response.headers["DAV"] = "1,2"
    head :ok
  end

  def handle_get
    if @file_path.directory?
      render html: directory_html.html_safe
    elsif @file_path.file?
      send_file @file_path, disposition: "inline"
    else
      head :not_found
    end
  end

  def handle_put
    FileUtils.mkdir_p(@file_path.dirname)

    File.open(@file_path, "wb") do |file|
      body = request.body
      file.write(body.respond_to?(:read) ? body.read : body.to_s)
    end

    # Ingest into DocSort (skip if directory marker or zero-byte collection)
    if @file_path.file? && @file_path.size.positive?
      File.open(@file_path, "rb") do |io|
        DocumentIngestor.new(
          io: io,
          filename: @file_path.basename.to_s,
          source: "webdav",
          content_type: request.media_type
        ).call
      end
    end

    Rails.logger.info("WebDAV PUT #{@file_path} (#{@file_path.size} bytes)")
    head :created
  rescue StandardError => e
    Rails.logger.error("WebDAV PUT failed: #{e.message}")
    render plain: e.message, status: :internal_server_error
  end

  def handle_delete
    if @file_path.exist?
      FileUtils.rm_rf(@file_path)
      head :no_content
    else
      head :not_found
    end
  end

  def handle_mkcol
    return head :method_not_allowed if @file_path.exist?

    FileUtils.mkdir_p(@file_path)
    head :created
  end

  def handle_propfind
    return head :not_found unless @file_path.exist?

    render xml: propfind_xml, content_type: "application/xml; charset=utf-8"
  end

  def handle_copy
    dest = destination_path
    return head :bad_request unless dest

    if @file_path.exist?
      FileUtils.mkdir_p(dest.dirname)
      FileUtils.cp_r(@file_path, dest)
      head :created
    else
      head :not_found
    end
  end

  def handle_move
    dest = destination_path
    return head :bad_request unless dest

    if @file_path.exist?
      FileUtils.mkdir_p(dest.dirname)
      FileUtils.mv(@file_path, dest)
      head :created
    else
      head :not_found
    end
  end

  def destination_path
    header = request.headers["Destination"]
    return nil if header.blank?

    uri = URI.parse(header)
    relative = uri.path.to_s.sub(%r{\A/webdav/?}, "")
    candidate = @upload_root.join(relative).cleanpath
    return nil unless candidate.to_s.start_with?(@upload_root.to_s)

    candidate
  rescue URI::InvalidURIError
    nil
  end

  def directory_html
    path = @relative
    rows = []
    rows << %(<li><a href="#{parent_url(path)}">..</a></li>) if path.present?

    Dir.children(@file_path).sort.each do |name|
      full = @file_path.join(name)
      href = path.present? ? "/webdav/#{path}/#{name}" : "/webdav/#{name}"
      if full.directory?
        rows << %(<li><a href="#{href}/">#{ERB::Util.html_escape(name)}/</a></li>)
      else
        rows << %(<li><a href="#{href}">#{ERB::Util.html_escape(name)}</a> (#{full.size} bytes)</li>)
      end
    end

    <<~HTML
      <!DOCTYPE html>
      <html><head><title>WebDAV inbox /#{ERB::Util.html_escape(path)}</title></head>
      <body>
        <h1>DocSort WebDAV inbox /#{ERB::Util.html_escape(path)}</h1>
        <p>Files uploaded here are classified and sorted automatically.</p>
        <ul>#{rows.join}</ul>
      </body></html>
    HTML
  end

  def parent_url(path)
    parent = File.dirname(path)
    parent == "." ? "/webdav/" : "/webdav/#{parent}/"
  end

  def propfind_xml
    href = "/webdav/#{@relative}"
    xml = +%(<?xml version="1.0" encoding="utf-8"?>)
    xml << %(<D:multistatus xmlns:D="DAV:">)
    xml << resource_xml(href, @file_path)

    if @file_path.directory?
      Dir.children(@file_path).each do |name|
        child = @file_path.join(name)
        child_href = href.end_with?("/") ? "#{href}#{name}" : "#{href}/#{name}"
        xml << resource_xml(child_href, child)
      end
    end

    xml << %(</D:multistatus>)
    xml
  end

  def resource_xml(href, path)
    xml = +%(<D:response><D:href>#{href}</D:href><D:propstat><D:prop>)
    if path.directory?
      xml << %(<D:resourcetype><D:collection/></D:resourcetype>)
    else
      xml << %(<D:resourcetype/>)
      xml << %(<D:getcontentlength>#{path.size}</D:getcontentlength>)
      xml << %(<D:getcontenttype>#{Rack::Mime.mime_type(path.extname, "application/octet-stream")}</D:getcontenttype>)
    end
    xml << %(<D:creationdate>#{path.ctime.iso8601}</D:creationdate>)
    xml << %(<D:getlastmodified>#{path.mtime.httpdate}</D:getlastmodified>)
    xml << %(</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>)
    xml
  end
end
