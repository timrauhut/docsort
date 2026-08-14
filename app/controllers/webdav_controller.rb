# Minimal WebDAV endpoint for drag-and-drop / Finder / curl uploads.
# Auth: same username/password as the web UI (User accounts).
# Each user has an isolated inbox under storage/inbox/<username>/.
class WebdavController < ApplicationController
  include ActionController::HttpAuthentication::Basic::ControllerMethods

  skip_before_action :require_login
  skip_before_action :require_secure_transport
  skip_before_action :require_password_change
  skip_before_action :verify_authenticity_token, raise: false
  before_action :require_secure_webdav
  before_action :authenticate_webdav_user
  before_action :reject_webdav_until_password_changed
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

  def authenticate_webdav_user
    authenticate_or_request_with_http_basic("DocSort WebDAV") do |username, password|
      user = User.authenticate(username, password)
      if user
        @webdav_user = user
        user.ensure_storage!
        true
      else
        false
      end
    end
  end

  def reject_webdav_until_password_changed
    return unless @webdav_user&.password_change_required?

    render plain: "Password change required. Sign in on the web and set a new password.", status: :forbidden
  end

  def require_secure_webdav
    return if request.ssl? || Rails.application.config.x.webdav.allow_insecure

    response.headers["Upgrade"] = "TLS/1.2, HTTP/1.1"
    render plain: "WebDAV requires HTTPS.", status: :upgrade_required
  end

  def set_paths
    return if performed?

    relative = params[:path].to_s
    @upload_root = Pathname.new(@webdav_user.inbox_root)
    FileUtils.mkdir_p(@upload_root)

    @file_path = SafeStoragePath.resolve(@upload_root, relative)
    @relative = relative
  rescue SafeStoragePath::UnsafePath
    head :bad_request
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
    if request.content_length.to_i > Rails.application.config.x.max_upload_bytes
      return render plain: upload_limit_message, status: :content_too_large
    end

    FileUtils.mkdir_p(@file_path.dirname)

    File.open(@file_path, "wb") do |file|
      copied = IO.copy_stream(request.body, file, Rails.application.config.x.max_upload_bytes + 1)
      raise DocumentIngestor::UploadTooLarge, upload_limit_message if copied > Rails.application.config.x.max_upload_bytes
    end

    if @file_path.file? && @file_path.size.positive?
      File.open(@file_path, "rb") do |io|
        DocumentIngestor.new(
          io: io,
          filename: @file_path.basename.to_s,
          source: "webdav",
          content_type: request.media_type,
          user: @webdav_user
        ).call
      end
    end

    Rails.logger.info("WebDAV PUT user=#{@webdav_user.username} path=#{@file_path} (#{@file_path.size} bytes)")
    head :created
  rescue DocumentIngestor::UploadTooLarge => e
    FileUtils.rm_f(@file_path)
    render plain: e.message, status: :content_too_large
  rescue DocumentIngestor::InvalidUpload => e
    FileUtils.rm_f(@file_path)
    render plain: e.message, status: :unsupported_media_type
  rescue StandardError => e
    Rails.logger.error("WebDAV PUT failed: #{e.message}")
    FileUtils.rm_f(@file_path)
    render plain: "Upload failed.", status: :internal_server_error
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
    SafeStoragePath.resolve(@upload_root, relative)
  rescue URI::InvalidURIError, SafeStoragePath::UnsafePath
    nil
  end

  def directory_html
    path = @relative
    rows = []
    rows << %(<li><a href="#{parent_url(path)}">..</a></li>) if path.present?

    Dir.children(@file_path).sort.each do |name|
      full = @file_path.join(name)
      href = webdav_href([ path.presence, name ].compact.join("/"))
      safe_href = ERB::Util.html_escape(href)
      if full.directory?
        rows << %(<li><a href="#{safe_href}/">#{ERB::Util.html_escape(name)}/</a></li>)
      else
        rows << %(<li><a href="#{safe_href}">#{ERB::Util.html_escape(name)}</a> (#{full.size} bytes)</li>)
      end
    end

    <<~HTML
      <!DOCTYPE html>
      <html><head><title>WebDAV inbox /#{ERB::Util.html_escape(path)}</title></head>
      <body>
        <h1>DocSort WebDAV — #{ERB::Util.html_escape(@webdav_user.username)} /#{ERB::Util.html_escape(path)}</h1>
        <p>Files uploaded here are classified and sorted into your private archive.</p>
        <ul>#{rows.join}</ul>
      </body></html>
    HTML
  end

  def parent_url(path)
    parent = File.dirname(path)
    parent == "." ? "/webdav/" : "#{webdav_href(parent)}/"
  end

  def propfind_xml
    href = webdav_href(@relative)
    xml = +%(<?xml version="1.0" encoding="utf-8"?>)
    xml << %(<D:multistatus xmlns:D="DAV:">)
    xml << resource_xml(href, @file_path)

    if @file_path.directory?
      Dir.children(@file_path).each do |name|
        child = @file_path.join(name)
        child_href = webdav_href([ @relative.presence, name ].compact.join("/"))
        xml << resource_xml(child_href, child)
      end
    end

    xml << %(</D:multistatus>)
    xml
  end

  def resource_xml(href, path)
    xml = +%(<D:response><D:href>#{ERB::Util.html_escape(href)}</D:href><D:propstat><D:prop>)
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

  def webdav_href(path)
    encoded = path.to_s.split("/").map { |segment| ERB::Util.url_encode(segment) }.join("/")
    encoded.present? ? "/webdav/#{encoded}" : "/webdav/"
  end

  def upload_limit_message
    megabytes = Rails.application.config.x.max_upload_bytes / 1.megabyte
    "Upload exceeds the #{megabytes} MB limit."
  end
end
