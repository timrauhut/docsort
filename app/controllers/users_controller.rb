class UsersController < ApplicationController
  before_action :require_admin
  before_action :set_user, only: %i[edit update destroy]

  def index
    @users = User.ordered
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    assign_admin_flag(@user)
    if @user.save
      @user.ensure_storage!
      redirect_to users_path, notice: "User “#{@user.username}” created. They can sign in and use WebDAV with the same password."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attrs = user_params
    attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?

    @user.assign_attributes(attrs)
    assign_admin_flag(@user)

    if @user.save
      @user.ensure_storage!
      redirect_to users_path, notice: "User “#{@user.username}” updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @user == current_user
      redirect_to users_path, alert: "You cannot delete your own account while signed in."
      return
    end

    if User.where(admin: true).where.not(id: @user.id).none? && @user.admin?
      redirect_to users_path, alert: "Keep at least one admin account."
      return
    end

    username = @user.username
    @user.destroy
    redirect_to users_path, notice: "User “#{username}” deleted."
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:username, :password, :password_confirmation)
  end

  def assign_admin_flag(user)
    return unless params.require(:user).key?(:admin)

    user.admin = ActiveModel::Type::Boolean.new.cast(params.require(:user)[:admin])
  end
end
