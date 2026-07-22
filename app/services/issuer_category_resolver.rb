# Maps a detected issuer (company/brand) to an existing category, or optionally
# creates a new category under issuers/<slug> as a potential filing home.
class IssuerCategoryResolver
  def initialize(issuer_name, confidence: 0.0, auto_create: nil)
    @issuer_name = issuer_name.to_s.strip
    @confidence = confidence.to_f
    @auto_create = auto_create.nil? ? Rails.application.config.x.auto_create_issuer_categories : auto_create
  end

  def call
    return nil if @issuer_name.blank?
    return nil if @confidence < 0.45

    find_existing || (create_issuer_category if @auto_create)
  end

  private

  def find_existing
    slug = @issuer_name.parameterize
    by_slug = Category.find_by(slug: slug) || Category.find_by(slug: "issuer-#{slug}")
    return by_slug if by_slug

    needle = @issuer_name.downcase
    Category.ordered.find do |category|
      category.name.downcase == needle ||
        category.name.downcase.include?(needle) ||
        needle.include?(category.name.downcase) ||
        category.keyword_list.any? { |kw| needle.include?(kw.downcase) || kw.downcase.include?(needle) }
    end
  end

  def create_issuer_category
    slug = "issuer-#{@issuer_name.parameterize}"
    path = File.join("issuers", @issuer_name.parameterize)

    category = Category.find_or_initialize_by(slug: slug)
    if category.new_record?
      category.assign_attributes(
        name: @issuer_name.truncate(60),
        directory_path: path,
        description: "Auto-created from document issuer / letterhead brand.",
        keywords: @issuer_name,
        auto_create: true,
        color: color_for(@issuer_name),
        position: 500
      )
      category.save!
      category.ensure_directory!
      Rails.logger.info("IssuerCategoryResolver: created category #{category.slug}")
    end
    category
  end

  def color_for(name)
    # Stable pastel-ish hex from name hash
    hue = name.each_byte.sum * 37 % 360
    # Convert HSL-ish to hex-ish fixed palette
    palette = %w[
      #0f766e #b45309 #7c3aed #be123c #0369a1
      #4d7c0f #c2410c #6d28d9 #0e7490 #a16207
    ]
    palette[hue % palette.length]
  end
end
