class CreateCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :categories do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :directory_path, null: false
      t.text :keywords
      t.boolean :auto_create, null: false, default: true
      t.integer :position, null: false, default: 0
      t.string :color, default: "#6366f1"

      t.timestamps
    end
    add_index :categories, :slug, unique: true
  end
end
