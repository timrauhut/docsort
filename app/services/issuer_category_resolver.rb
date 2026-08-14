# Maps a detected issuer (company/brand) to an existing category, or optionally
# creates a new category under issuers/<slug> as a potential filing home.
class IssuerCategoryResolver
  MIN_KEYWORD_LENGTH = 4

  def initialize(issuer_name, user:, confidence: 0.0, auto_create: nil)
    raise ArgumentError, "user required" if user.blank?

    @issuer_name = issuer_name.to_s.strip
    @user = user
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
    scope = Category.visible_to(@user)
    slug = @issuer_name.parameterize
    by_slug = scope.find_by(slug: slug) || scope.find_by(slug: "issuer-#{slug}")
    return by_slug if by_slug

    needle = @issuer_name.downcase
    scope.ordered.find do |category|
      name = category.name.to_s.downcase.strip
      next true if name == needle
      next true if name.parameterize == slug

      # Keywords only: whole-token match, min length (no short bidirectional includes).
      category.keyword_list.any? { |kw| keyword_token_match?(needle, kw) }
    end
  end

  def keyword_token_match?(needle, keyword)
    token = keyword.to_s.downcase.strip
    return false if token.length < MIN_KEYWORD_LENGTH

    needle == token || needle.match?(/\b#{Regexp.escape(token)}\b/i)
  end

  def create_issuer_category
    slug = "issuer-#{@issuer_name.parameterize}"
    path = File.join("issuers", @issuer_name.parameterize)

    category = Category.find_or_initialize_by(slug: slug, user: @user)
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
      category.ensure_directory!(@user.sorted_root)
      Rails.logger.info("IssuerCategoryResolver: created category #{category.slug}")
    end
    category
  end

  def color_for(name)
    # Stable muted tones that sit with buzz.xyz chartreuse/ink UI
    hue = name.each_byte.sum * 37 % 360
    palette = %w[
      #5b7c99 #3d7a6a #6b5f7a #8a7a32 #5a6570
      #7a5c5c #5c5a52 #6a7a5a #7a6a4a #4a6a7a
    ]
    palette[hue % palette.length]
  end
end
