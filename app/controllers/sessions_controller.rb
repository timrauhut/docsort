class SessionsController < ApplicationController
  skip_before_action :require_login, only: %i[new create]
  allow_browser versions: :modern

  def new
    redirect_to root_path if logged_in?
  end

  def create
    user = User.authenticate(params[:username], params[:password])
    if user
      reset_session
      session[:user_id] = user.id
      user.ensure_storage!
      redirect_to(session.delete(:return_to).presence || root_path, notice: "Signed in as #{user.username}.")
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
