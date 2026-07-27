class User < ApplicationRecord
  has_secure_password

  has_many :documents, dependent: :destroy

  validates :username,
            presence: true,
            uniqueness: { case_sensitive: false },
            length: { minimum: 2, maximum: 40 },
            format: {
              with: /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/,
              message: "may only contain letters, numbers, dots, underscores, and hyphens"
            }
  validates :password, length: { minimum: 6, maximum: 72 }, if: -> { password.present? }

  before_validation :normalize_username

  scope :ordered, -> { order(:username) }

  def inbox_root
    File.join(Rails.application.config.x.inbox_root, username)
  end

  def sorted_root
    File.join(Rails.application.config.x.sorted_root, username)
  end

  def ensure_storage!
    FileUtils.mkdir_p(inbox_root)
    FileUtils.mkdir_p(sorted_root)
  end

  def self.authenticate(username, password)
    user = find_by("LOWER(username) = ?", username.to_s.strip.downcase)
    user&.authenticate(password) || nil
  end

  private

  def normalize_username
    self.username = username.to_s.strip.downcase
  end
end
