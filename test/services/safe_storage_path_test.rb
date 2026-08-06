require "test_helper"

class SafeStoragePathTest < ActiveSupport::TestCase
  test "allows descendants of the storage root" do
    root = Pathname.new(Dir.mktmpdir("docsort-safe-root"))
    assert_equal root.join("folder/file.pdf"), SafeStoragePath.resolve(root, "folder/file.pdf")
  ensure
    FileUtils.rm_rf(root) if root
  end

  test "rejects sibling paths sharing the root prefix" do
    parent = Pathname.new(Dir.mktmpdir("docsort-safe-parent"))
    root = parent.join("ann")
    root.mkdir

    assert_raises(SafeStoragePath::UnsafePath) do
      SafeStoragePath.resolve(root, "../anna/private.pdf")
    end
  ensure
    FileUtils.rm_rf(parent) if parent
  end

  test "rejects absolute and parent-relative category paths" do
    refute SafeStoragePath.safe_relative?("/tmp/outside")
    refute SafeStoragePath.safe_relative?("finance/../../outside")
    assert SafeStoragePath.safe_relative?("finance/invoices")
  end
end
