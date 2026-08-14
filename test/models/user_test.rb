require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    @previous_inbox = Rails.application.config.x.inbox_root
    @previous_sorted = Rails.application.config.x.sorted_root
    @inbox_root = Pathname.new(Dir.mktmpdir("docsort-user-inbox"))
    @sorted_root = Pathname.new(Dir.mktmpdir("docsort-user-sorted"))
    Rails.application.config.x.inbox_root = @inbox_root.to_s
    Rails.application.config.x.sorted_root = @sorted_root.to_s
  end

  teardown do
    Rails.application.config.x.inbox_root = @previous_inbox
    Rails.application.config.x.sorted_root = @previous_sorted
    FileUtils.rm_rf(@inbox_root)
    FileUtils.rm_rf(@sorted_root)
  end

  test "renaming a user moves storage trees off the old username" do
    user = users(:alice)
    user.ensure_storage!
    File.write(File.join(user.inbox_root, "scan.txt"), "inbox")
    FileUtils.mkdir_p(File.join(user.sorted_root, "unsorted"))
    File.write(File.join(user.sorted_root, "unsorted", "scan.txt"), "sorted")
    document = documents(:pending_doc)
    document.update!(user: user, relative_path: "alice/unsorted/scan.txt")

    user.update!(username: "alice-renamed")

    assert File.exist?(File.join(@inbox_root, "alice-renamed", "scan.txt"))
    assert File.exist?(File.join(@sorted_root, "alice-renamed", "unsorted", "scan.txt"))
    assert_equal "alice-renamed/unsorted/scan.txt", document.reload.relative_path
    assert_equal Pathname.new(File.join(@sorted_root, "alice-renamed", "unsorted", "scan.txt")), SortedCopy.path_for(document)
    refute File.exist?(File.join(@inbox_root, "alice"))
    refute File.exist?(File.join(@sorted_root, "alice"))
  end

  test "renaming a user refuses to overwrite an existing storage tree" do
    user = users(:alice)
    user.ensure_storage!
    File.write(File.join(user.inbox_root, "original.txt"), "keep me")
    destination = File.join(@inbox_root, "occupied")
    FileUtils.mkdir_p(destination)
    File.write(File.join(destination, "other.txt"), "also keep me")

    refute user.update(username: "occupied")

    assert_includes user.errors[:username], "already has a storage directory; move or remove it before renaming"
    assert File.exist?(File.join(@inbox_root, "alice", "original.txt"))
    assert File.exist?(File.join(destination, "other.txt"))
  end

  test "destroying a user purges inbox and sorted trees" do
    user = users(:alice)
    user.ensure_storage!
    File.write(File.join(user.inbox_root, "scan.txt"), "inbox")

    user.destroy!

    refute File.exist?(File.join(@inbox_root, "alice"))
    refute File.exist?(File.join(@sorted_root, "alice"))
  end

  test "weak bootstrap passwords are rejected in production seeding" do
    assert User.weak_bootstrap_password?("changeme")
    assert User.weak_bootstrap_password?("upload123")
    assert User.weak_bootstrap_password?("")
    refute User.weak_bootstrap_password?("a-long-random-secret")
  end
end
