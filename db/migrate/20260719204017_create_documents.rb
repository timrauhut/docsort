class CreateDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :documents do |t|
      t.string :title
      t.string :original_filename, null: false
      t.string :status, null: false, default: "pending"
      t.text :summary
      t.text :extracted_text
      t.string :content_type
      t.integer :byte_size
      t.float :confidence
      t.text :tags
      t.string :source, null: false, default: "web"
      t.string :relative_path
      t.references :category, null: true, foreign_key: true
      t.datetime :classified_at
      t.text :error_message
      t.json :metadata, default: {}
      t.string :classifier_used

      t.timestamps
    end

    add_index :documents, :status
    add_index :documents, :source
    add_index :documents, :original_filename
  end
end
