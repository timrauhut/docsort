require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  test "directory path must stay relative" do
    category = Category.new(name: "Unsafe", slug: "unsafe", directory_path: "../outside")

    refute category.valid?
    assert category.errors[:directory_path].present?
  end

  test "visible_to includes shared and owned categories only" do
    owned = Category.create!(
      name: "Alice Bank",
      slug: "issuer-alice-bank",
      directory_path: "issuers/alice-bank",
      user: users(:alice)
    )
    foreign = Category.create!(
      name: "Admin Bank",
      slug: "issuer-admin-bank",
      directory_path: "issuers/admin-bank",
      user: users(:admin)
    )

    visible = Category.visible_to(users(:alice))
    assert_includes visible, categories(:invoices)
    assert_includes visible, owned
    refute_includes visible, foreign
  end
  # test "the truth" do
  #   assert true
  # end
end
