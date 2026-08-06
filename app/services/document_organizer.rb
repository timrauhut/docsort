# Ensures category directories exist and places a sorted copy of the document
# under storage/sorted/<username>/<category_path>[/<issuer_slug>]/<filename>.
class DocumentOrganizer
  def initialize(document)
    @document = document
  end

  def call
    category = @document.category
    return unless category
    return unless @document.file.attached?
    return unless @document.user

    dir = target_directory(category)
    FileUtils.mkdir_p(dir)

    previous_path = SortedCopy.path_for(@document)
    target_name = target_filename(dir, previous_path)
    target_path = File.join(dir, target_name)

    Tempfile.create([ "docsort-sort-", File.extname(target_name) ], dir) do |staging|
      @document.file.blob.open do |source|
        IO.copy_stream(source, staging)
      end
      staging.flush
      FileUtils.mv(staging.path, target_path)
    end

    previous_path.delete if previous_path&.file? && previous_path.to_s != target_path

    relative = Pathname.new(target_path).relative_path_from(
      Pathname.new(Rails.application.config.x.sorted_root)
    ).to_s
    @document.update!(relative_path: relative)
    relative
  end

  private

  def target_directory(category)
    base = SafeStoragePath.resolve(@document.user.sorted_root, category.directory_path)
    # Nest under issuer when we have one and category is not already an issuer-* folder
    if @document.issuer.present? && !category.slug.to_s.start_with?("issuer-")
      SafeStoragePath.resolve(base, @document.issuer.parameterize)
    else
      base
    end
  end

  def target_filename(dir, previous_path)
    base = File.basename(@document.original_filename.to_s)
    return base if previous_path&.dirname == Pathname.new(dir) && previous_path.basename.to_s == base

    unique_filename(dir, base)
  end

  def unique_filename(dir, original)
    base = File.basename(original.to_s)
    return base unless File.exist?(File.join(dir, base))

    ext = File.extname(base)
    stem = File.basename(base, ext)
    n = 1
    loop do
      candidate = "#{stem}-#{n}#{ext}"
      return candidate unless File.exist?(File.join(dir, candidate))

      n += 1
    end
  end
end
