class ScopeIssuerCategoriesToUsers < ActiveRecord::Migration[8.1]
  class MigrationCategory < ApplicationRecord
    self.table_name = "categories"
  end

  class MigrationDocument < ApplicationRecord
    self.table_name = "documents"
  end

  class MigrationUser < ApplicationRecord
    self.table_name = "users"
  end

  class MigrationClassificationRule < ApplicationRecord
    self.table_name = "classification_rules"
  end

  def up
    add_reference :categories, :user, foreign_key: true, null: true

    remove_index :categories, :slug
    add_index :categories, :slug, unique: true, where: "user_id IS NULL"
    add_index :categories, [ :user_id, :slug ], unique: true, where: "user_id IS NOT NULL"

    say_with_time "scoping existing issuer categories to document owners" do
      fallback_owner_id = MigrationUser.where(admin: true).order(:id).pick(:id) || MigrationUser.order(:id).pick(:id)

      MigrationCategory.where("slug LIKE ?", "issuer-%").where(user_id: nil).find_each do |category|
        owner_ids = MigrationDocument.where(category_id: category.id).distinct.pluck(:user_id).compact
        owner_ids << fallback_owner_id if owner_ids.empty? && fallback_owner_id
        next if owner_ids.empty?

        primary_id = owner_ids.shift
        category.update!(user_id: primary_id)

        owner_ids.each do |user_id|
          clone = MigrationCategory.create!(
            category.attributes.except("id", "created_at", "updated_at").merge("user_id" => user_id)
          )
          MigrationDocument.where(category_id: category.id, user_id: user_id).update_all(category_id: clone.id)
        end
      end
    end
  end

  def down
    say_with_time "consolidating per-user categories for global slug uniqueness" do
      duplicate_slugs = MigrationCategory.group(:slug).having("COUNT(*) > 1").pluck(:slug)

      duplicate_slugs.each do |slug|
        categories = MigrationCategory.where(slug: slug).order(Arel.sql("user_id IS NOT NULL"), :id).to_a
        keeper = categories.shift

        categories.each do |duplicate|
          MigrationDocument.where(category_id: duplicate.id).update_all(category_id: keeper.id)
          MigrationClassificationRule.where(category_id: duplicate.id).update_all(category_id: keeper.id)
          duplicate.delete
        end
      end
    end

    remove_index :categories, [ :user_id, :slug ]
    remove_index :categories, :slug
    remove_reference :categories, :user, foreign_key: true
    add_index :categories, :slug, unique: true
  end
end
