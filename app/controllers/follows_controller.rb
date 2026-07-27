class FollowsController < ApplicationController
  before_action :set_user

  def create
    if current_user.follow(@user)
      redirect_back fallback_location: users_path, notice: "You are now following #{@user.username}."
    else
      redirect_back fallback_location: users_path, alert: "Could not follow #{@user.username}."
    end
  end

  def destroy
    current_user.unfollow(@user)
    redirect_back fallback_location: users_path, notice: "You unfollowed #{@user.username}."
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end
end
