require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin)
    @user.update!(password_change_required: true)
  end

  test "initial login redirects to password setup" do
    post login_path, params: { username: @user.username, password: "password123" }

    assert_redirected_to edit_account_path
  end

  test "required password change blocks the rest of the app" do
    sign_in

    get documents_path

    assert_redirected_to edit_account_path
  end

  test "incorrect installation password is rejected" do
    sign_in

    patch account_path, params: {
      account: {
        current_password: "incorrect",
        password: "new-password-123",
        password_confirmation: "new-password-123"
      }
    }

    assert_response :unprocessable_entity
    assert @user.reload.password_change_required?
  end

  test "user can replace installation password and finish setup" do
    sign_in

    patch account_path, params: {
      account: {
        current_password: "password123",
        password: "new-password-123",
        password_confirmation: "new-password-123"
      }
    }

    assert_redirected_to root_path
    assert_not @user.reload.password_change_required?
    assert @user.authenticate("new-password-123")
  end

  test "blank new password cannot bypass setup" do
    sign_in

    patch account_path, params: {
      account: {
        current_password: "password123",
        password: "",
        password_confirmation: ""
      }
    }

    assert_response :unprocessable_entity
    assert @user.reload.password_change_required?
    assert @user.authenticate("password123")
  end

  test "installation password must actually be replaced" do
    sign_in

    patch account_path, params: {
      account: {
        current_password: "password123",
        password: "password123",
        password_confirmation: "password123"
      }
    }

    assert_response :unprocessable_entity
    assert @user.reload.password_change_required?
  end

  private

  def sign_in
    post login_path, params: { username: @user.username, password: "password123" }
  end
end
