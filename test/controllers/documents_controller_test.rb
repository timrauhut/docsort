require "test_helper"

class DocumentsControllerTest < ActionDispatch::IntegrationTest
  test "users cannot access another users document" do
    sign_in_as(users(:alice))

    get document_path(documents(:invoice_doc))

    assert_response :not_found
  end

  test "download stays on the authenticated document action" do
    document = documents(:pending_doc)
    document.file.attach(
      io: StringIO.new("private notes"),
      filename: "notes.txt",
      content_type: "text/plain"
    )
    sign_in_as(users(:alice))

    get download_document_path(document)

    assert_response :success
    assert_equal "private notes", response.body
    assert_match(/attachment/, response.headers["Content-Disposition"].to_s)
    refute_match(%r{/rails/active_storage}, response.location.to_s)
  end

  test "users cannot assign another users issuer category" do
    foreign = Category.create!(
      name: "Secret Bank",
      slug: "issuer-secret-bank",
      directory_path: "issuers/secret-bank",
      user: users(:admin)
    )
    document = documents(:pending_doc)
    sign_in_as(users(:alice))

    post assign_document_path(document), params: { category_id: foreign.id }

    assert_response :not_found
  end

  private

  def sign_in_as(user)
    post login_path, params: { username: user.username, password: "password123" }
    assert_redirected_to root_path
  end
end
