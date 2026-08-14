class Category < ApplicationRecord
  belongs_to :user, optional: true
  has_many :documents, dependent: :nullify
  has_many :classification_rules, dependent: :destroy

  validates :name, :slug, :directory_path, presence: true
  validates :slug, uniqueness: { scope: :user_id }, format: { with: /\A[a-z0-9\-]+\z/ }
  validate :directory_path_is_safe

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }
  before_validation :default_directory_path, if: -> { directory_path.blank? && slug.present? }

  scope :ordered, -> { order(:position, :name) }
  scope :shared, -> { where(user_id: nil) }
  scope :visible_to, lambda { |user|
    return none if user.blank?

    where("categories.user_id IS NULL OR categories.user_id = ?", user.id)
  }

  def keyword_list
    keywords.to_s.split(/[,\n]/).map(&:strip).reject(&:blank?)
  end

  def self.issuer_for(user, issuer_name)
    slug = issuer_name.to_s.parameterize
    return if slug.blank?

    visible_to(user).find_by(slug: "issuer-#{slug}")
  end

  def ensure_directory!(root = nil)
    return unless auto_create?

    base = root.presence || user&.sorted_root || Rails.application.config.x.sorted_root
    path = SafeStoragePath.resolve(base, directory_path)
    FileUtils.mkdir_p(path)
    path
  end

  def absolute_directory
    base = user&.sorted_root || Rails.application.config.x.sorted_root
    SafeStoragePath.resolve(base, directory_path).to_s
  end

  private

  def generate_slug
    self.slug = name.to_s.parameterize
  end

  def default_directory_path
    self.directory_path = slug
  end

  def directory_path_is_safe
    return if directory_path.blank? || SafeStoragePath.safe_relative?(directory_path)

    errors.add(:directory_path, "must be a relative path without empty, dot, or parent segments")
  end
end
