require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  test "directory path must stay relative" do
    category = Category.new(name: "Unsafe", slug: "unsafe", directory_path: "../outside")

    refute category.valid?
    assert category.errors[:directory_path].present?
  end
  # test "the truth" do
  #   assert true
  # end
end
