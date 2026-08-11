class SessionsController < ApplicationController
  skip_before_action :require_login, only: %i[new create]
  skip_before_action :require_password_change
  allow_browser versions: :modern

  def new
    redirect_to root_path if logged_in?
  end

  def create
    user = User.authenticate(params[:username], params[:password])
    if user
      return_to = session.delete(:return_to)
      reset_session
      session[:user_id] = user.id
      user.ensure_storage!
      destination = user.password_change_required? ? edit_account_path : return_to.presence || root_path
      notice = user.password_change_required? ? "Choose a new password to finish setup." : "Signed in as #{user.username}."
      redirect_to destination, notice: notice
    else
      flash.now[:alert] = "Invalid username or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "Signed out."
  end
end
