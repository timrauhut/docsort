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

    target_name = unique_filename(dir, @document.original_filename)
    target_path = File.join(dir, target_name)

    @document.file.blob.open do |tempfile|
      FileUtils.cp(tempfile.path, target_path)
    end

    relative = Pathname.new(target_path).relative_path_from(
      Pathname.new(Rails.application.config.x.sorted_root)
    ).to_s
    @document.update!(relative_path: relative)
    relative
  end

  private

  def target_directory(category)
    base = File.join(@document.user.sorted_root, category.directory_path)
    # Nest under issuer when we have one and category is not already an issuer-* folder
    if @document.issuer.present? && !category.slug.to_s.start_with?("issuer-")
      File.join(base, @document.issuer.parameterize)
    else
      base
    end
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
