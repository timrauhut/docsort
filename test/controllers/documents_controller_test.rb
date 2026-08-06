require "test_helper"

class DocumentsControllerTest < ActionDispatch::IntegrationTest
  test "users cannot access another users document" do
    sign_in_as(users(:alice))

    get document_path(documents(:invoice_doc))

    assert_response :not_found
  end

  private

  def sign_in_as(user)
    post login_path, params: { username: user.username, password: "password123" }
    assert_redirected_to root_path
  end
end
