require "test_helper"

class SortedCopyTest < ActiveSupport::TestCase
  setup do
    @previous_sorted_root = Rails.application.config.x.sorted_root
    @sorted_root = Pathname.new(Dir.mktmpdir("docsort-sorted"))
    Rails.application.config.x.sorted_root = @sorted_root.to_s
  end

  teardown do
    Rails.application.config.x.sorted_root = @previous_sorted_root
    FileUtils.rm_rf(@sorted_root)
  end

  test "reorganizing removes the previous sorted copy" do
    document = documents(:invoice_doc)
    document.file.attach(io: StringIO.new("invoice"), filename: "invoice-001.pdf", content_type: "application/pdf")

    DocumentOrganizer.new(document).call
    old_path = SortedCopy.path_for(document)
    assert old_path.file?

    other = categories(:unsorted)
    document.update!(category: other)
    DocumentOrganizer.new(document).call

    refute old_path.exist?
    assert SortedCopy.path_for(document).file?
  end

  test "destroying a document removes its sorted copy" do
    document = documents(:invoice_doc)
    document.file.attach(io: StringIO.new("invoice"), filename: "invoice-001.pdf", content_type: "application/pdf")
    DocumentOrganizer.new(document).call
    path = SortedCopy.path_for(document)

    document.destroy!

    refute path.exist?
  end
end
