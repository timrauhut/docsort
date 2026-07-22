class ClassificationRule < ApplicationRecord
  belongs_to :category

  validates :name, :pattern, presence: true
  validates :priority, numericality: { only_integer: true }

  scope :active, -> { where(active: true) }
  scope :by_priority, -> { order(:priority, :id) }

  def matches?(text)
    return false if text.blank?

    Regexp.new(pattern, Regexp::IGNORECASE).match?(text.to_s)
  rescue RegexpError
    false
  end
end
