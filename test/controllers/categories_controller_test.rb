require "test_helper"

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    post login_path, params: { username: "admin", password: "password123" }
  end

  test "non-admin users cannot mutate the shared category catalog" do
    delete logout_path
    post login_path, params: { username: "alice", password: "password123" }

    get new_category_path

    assert_redirected_to root_path
  end

  test "rejects a directory path outside the users sorted root" do
    assert_no_difference("Category.count") do
      post categories_path, params: {
        category: {
          name: "Escape",
          slug: "escape",
          directory_path: "../../admin/private",
          position: 1,
          color: "#231e1e"
        }
      }
    end

    assert_response :unprocessable_entity
  end
end
