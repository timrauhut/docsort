class User < ApplicationRecord
  has_secure_password

  has_many :documents, dependent: :destroy

  has_many :active_relationships,
           class_name: "Follow",
           foreign_key: :follower_id,
           dependent: :destroy,
           inverse_of: :follower
  has_many :passive_relationships,
           class_name: "Follow",
           foreign_key: :followed_id,
           dependent: :destroy,
           inverse_of: :followed
  has_many :following, through: :active_relationships, source: :followed
  has_many :followers, through: :passive_relationships, source: :follower

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

  def follow(other_user)
    return false if other_user.blank? || other_user == self

    following << other_user unless following?(other_user)
    true
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    following?(other_user)
  end

  def unfollow(other_user)
    following.delete(other_user)
  end

  def following?(other_user)
    return false if other_user.blank?

    if following.loaded?
      following.include?(other_user)
    else
      following.exists?(id: other_user.id)
    end
  end

  private

  def normalize_username
    self.username = username.to_s.strip.downcase
  end
end

