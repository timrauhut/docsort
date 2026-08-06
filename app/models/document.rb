class Document < ApplicationRecord
  STATUSES = %w[pending processing classified failed unsorted].freeze
  SOURCES = %w[web webdav api].freeze

  # UUID primary keys are not chronological; order by created_at instead.
  self.implicit_order_column = "created_at"

  belongs_to :user
  belongs_to :category, optional: true
  has_one_attached :file

  before_create :assign_uuid
  after_destroy_commit :remove_sorted_copy

  validates :original_filename, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }

  scope :recent, -> { order(created_at: :desc) }
  scope :pending, -> { where(status: %w[pending processing]) }
  scope :classified, -> { where(status: "classified") }
  scope :failed, -> { where(status: "failed") }
  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :by_category, ->(category_id) { where(category_id: category_id) if category_id.present? }
  scope :search, lambda { |query|
    return all if query.blank?

    pattern = "%#{sanitize_sql_like(query)}%"
    where(
      "title LIKE :q OR original_filename LIKE :q OR summary LIKE :q OR tags LIKE :q OR extracted_text LIKE :q OR issuer LIKE :q",
      q: pattern
    )
  }

  def tag_list
    tags.to_s.split(/[,\n]/).map(&:strip).reject(&:blank?)
  end

  def tag_list=(value)
    self.tags = Array(value).flat_map { |v| v.to_s.split(",") }.map(&:strip).reject(&:blank?).join(", ")
  end

  def display_title
    title.presence || original_filename
  end

  def human_size
    return "—" if byte_size.blank?

    units = %w[B KB MB GB]
    size = byte_size.to_f
    unit = 0
    while size >= 1024 && unit < units.length - 1
      size /= 1024.0
      unit += 1
    end
    format("%.1f %s", size, units[unit])
  end

  # Kept for any remaining view references; prefer status_badge helper.
  def status_badge_class
    case status
    when "classified" then "badge badge-classified"
    when "processing", "pending" then "badge badge-pending"
    when "failed" then "badge badge-failed"
    else "badge badge-unsorted"
    end
  end

  def reclassify!
    update!(
      status: "pending",
      error_message: nil,
      classified_at: nil,
      confidence: nil,
      classifier_used: nil
    )
    ClassifyDocumentJob.perform_later(id)
  end

  private

  def assign_uuid
    self.id ||= SecureRandom.uuid_v7
  end

  def remove_sorted_copy
    SortedCopy.remove(self)
  end
end
