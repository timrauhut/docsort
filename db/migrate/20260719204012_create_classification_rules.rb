class CreateClassificationRules < ActiveRecord::Migration[8.1]
  def change
    create_table :classification_rules do |t|
      t.string :name, null: false
      t.string :pattern, null: false
      t.references :category, null: false, foreign_key: true
      t.integer :priority, null: false, default: 100
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :classification_rules, :priority
  end
end
