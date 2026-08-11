class AccountsController < ApplicationController
  def edit
  end

  def update
    unless current_user.authenticate(account_params[:current_password])
      current_user.errors.add(:current_password, "is incorrect")
      render :edit, status: :unprocessable_entity
      return
    end

    if account_params[:password].blank?
      current_user.errors.add(:password, "can't be blank")
      render :edit, status: :unprocessable_entity
      return
    end

    if current_user.authenticate(account_params[:password])
      current_user.errors.add(:password, "must be different from the installation password")
      render :edit, status: :unprocessable_entity
      return
    end

    if current_user.update(
      password: account_params[:password],
      password_confirmation: account_params[:password_confirmation],
      password_change_required: false
    )
      redirect_to root_path, notice: "Password updated. DocSort is ready."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def account_params
    params.require(:account).permit(:current_password, :password, :password_confirmation)
  end
end
