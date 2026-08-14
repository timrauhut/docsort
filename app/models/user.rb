class User < ApplicationRecord
  WEAK_BOOTSTRAP_PASSWORDS = %w[changeme upload123 password password123 admin].freeze

  has_secure_password

  has_many :documents, dependent: :destroy
  has_many :categories, dependent: :destroy

  validates :username,
            presence: true,
            uniqueness: { case_sensitive: false },
            length: { minimum: 2, maximum: 40 },
            format: {
              with: /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/,
              message: "may only contain letters, numbers, dots, underscores, and hyphens"
            }
  validates :password, length: { minimum: 6, maximum: 72 }, if: -> { password.present? }
  validate :storage_destination_must_be_available, if: :will_save_change_to_username?

  before_validation :normalize_username
  after_update :relocate_storage_trees, if: :saved_change_to_username?
  after_destroy_commit :purge_storage_trees

  scope :ordered, -> { order(:username) }

  def inbox_root
    File.join(Rails.application.config.x.inbox_root, username)
  end

  def sorted_root
    File.join(Rails.application.config.x.sorted_root, username)
  end

  def assignable_categories
    Category.visible_to(self).ordered
  end

  def ensure_storage!
    FileUtils.mkdir_p(inbox_root)
    FileUtils.mkdir_p(sorted_root)
  end

  def self.authenticate(username, password)
    user = find_by("LOWER(username) = ?", username.to_s.strip.downcase)
    user&.authenticate(password) || nil
  end

  def self.weak_bootstrap_password?(password)
    value = password.to_s
    value.blank? || WEAK_BOOTSTRAP_PASSWORDS.include?(value)
  end

  private

  def normalize_username
    self.username = username.to_s.strip.downcase
  end

  def relocate_storage_trees
    old_username, = saved_change_to_username
    return if old_username.blank?

    relocate_tree(File.join(Rails.application.config.x.inbox_root, old_username), inbox_root)
    relocate_tree(File.join(Rails.application.config.x.sorted_root, old_username), sorted_root)
    relocate_document_paths(old_username)
  end

  def purge_storage_trees
    remove_storage_tree(inbox_root)
    remove_storage_tree(sorted_root)
  end

  def relocate_tree(old_path, new_path)
    old_dir = Pathname.new(old_path).expand_path
    new_dir = Pathname.new(new_path).expand_path
    return unless storage_leaf?(old_dir)
    return unless storage_leaf?(new_dir)
    return unless old_dir.exist?

    raise "storage destination already exists: #{new_dir}" if new_dir.exist?

    FileUtils.mkdir_p(new_dir.dirname)
    FileUtils.mv(old_dir.to_s, new_dir.to_s)
  end

  def relocate_document_paths(old_username)
    prefix = "#{old_username}/"
    documents.where.not(relative_path: nil).find_each do |document|
      next unless document.relative_path.start_with?(prefix)

      document.update_column(:relative_path, document.relative_path.sub(/\A#{Regexp.escape(prefix)}/, "#{username}/"))
    end
  end

  def storage_destination_must_be_available
    return unless username.present?

    destinations = [
      Pathname.new(File.join(Rails.application.config.x.inbox_root, username)).expand_path,
      Pathname.new(File.join(Rails.application.config.x.sorted_root, username)).expand_path
    ]
    return unless destinations.any?(&:exist?)

    errors.add(:username, "already has a storage directory; move or remove it before renaming")
  end

  def remove_storage_tree(path)
    pathname = Pathname.new(path).expand_path
    return unless storage_leaf?(pathname)
    return unless pathname.exist?

    FileUtils.rm_rf(pathname)
  end

  def storage_leaf?(path)
    inbox = Pathname.new(Rails.application.config.x.inbox_root).expand_path
    sorted = Pathname.new(Rails.application.config.x.sorted_root).expand_path
    return false if path == inbox || path == sorted

    SafeStoragePath.contained?(inbox, path) || SafeStoragePath.contained?(sorted, path)
  end
end
