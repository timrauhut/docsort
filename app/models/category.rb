class Category < ApplicationRecord
  has_many :documents, dependent: :nullify
  has_many :classification_rules, dependent: :destroy

  validates :name, :slug, :directory_path, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/ }

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }
  before_validation :default_directory_path, if: -> { directory_path.blank? && slug.present? }

  scope :ordered, -> { order(:position, :name) }

  def keyword_list
    keywords.to_s.split(/[,\n]/).map(&:strip).reject(&:blank?)
  end

  def ensure_directory!
    return unless auto_create?

    path = File.join(Rails.application.config.x.sorted_root, directory_path)
    FileUtils.mkdir_p(path)
    path
  end

  def absolute_directory
    File.join(Rails.application.config.x.sorted_root, directory_path)
  end

  private

  def generate_slug
    self.slug = name.to_s.parameterize
  end

  def default_directory_path
    self.directory_path = slug
  end
end
