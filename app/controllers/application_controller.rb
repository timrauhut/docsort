class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_secure_transport
  before_action :require_login
  before_action :require_password_change

  helper_method :current_user, :logged_in?

  private

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def logged_in?
    current_user.present?
  end

  def require_login
    return if logged_in?

    session[:return_to] = request.fullpath if request.get? || request.head?
    redirect_to login_path, alert: "Please sign in to continue."
  end

  def require_secure_transport
    return if request.ssl? || Rails.application.config.x.allow_insecure_auth

    response.headers["Upgrade"] = "TLS/1.2, HTTP/1.1"
    render plain: "DocSort authentication requires HTTPS.", status: :upgrade_required
  end

  def require_admin
    return if current_user&.admin?

    redirect_to root_path, alert: "Admin access required."
  end

  def require_password_change
    return unless current_user&.password_change_required?
    return if controller_name == "accounts"

    redirect_to edit_account_path, alert: "Choose a new password to finish setting up DocSort."
  end
end
