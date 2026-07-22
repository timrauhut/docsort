# frozen_string_literal: true

class ConvertDocumentIdsToUuid < ActiveRecord::Migration[8.1]
  def up
    mapping = {}

    create_table :documents_new, id: false do |t|
      t.string :id, null: false, primary_key: true
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
      t.integer :category_id
      t.datetime :classified_at
      t.text :error_message
      t.json :metadata, default: {}
      t.string :classifier_used
      t.string :issuer
      t.float :issuer_confidence
      t.integer :user_id
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end

    add_index :documents_new, :category_id
    add_index :documents_new, :issuer
    add_index :documents_new, :original_filename
    add_index :documents_new, :source
    add_index :documents_new, :status
    add_index :documents_new, :user_id

    say_with_time "copying documents to uuid primary keys" do
      select_all("SELECT * FROM documents ORDER BY id").each do |row|
        new_id = SecureRandom.uuid_v7
        mapping[row["id"].to_s] = new_id

        execute <<~SQL.squish
          INSERT INTO documents_new (
            id, title, original_filename, status, summary, extracted_text,
            content_type, byte_size, confidence, tags, source, relative_path,
            category_id, classified_at, error_message, metadata, classifier_used,
            issuer, issuer_confidence, user_id, created_at, updated_at
          ) VALUES (
            #{quote(new_id)},
            #{quote(row["title"])},
            #{quote(row["original_filename"])},
            #{quote(row["status"])},
            #{quote(row["summary"])},
            #{quote(row["extracted_text"])},
            #{quote(row["content_type"])},
            #{quote(row["byte_size"])},
            #{quote(row["confidence"])},
            #{quote(row["tags"])},
            #{quote(row["source"])},
            #{quote(row["relative_path"])},
            #{quote(row["category_id"])},
            #{quote(row["classified_at"])},
            #{quote(row["error_message"])},
            #{quote(row["metadata"])},
            #{quote(row["classifier_used"])},
            #{quote(row["issuer"])},
            #{quote(row["issuer_confidence"])},
            #{quote(row["user_id"])},
            #{quote(row["created_at"])},
            #{quote(row["updated_at"])}
          )
        SQL
      end
    end

    # Polymorphic Active Storage record_id must hold UUIDs for Document attachments.
    change_column :active_storage_attachments, :record_id, :string, null: false

    say_with_time "remapping active_storage attachments for documents" do
      mapping.each do |old_id, new_id|
        execute <<~SQL.squish
          UPDATE active_storage_attachments
          SET record_id = #{quote(new_id)}
          WHERE record_type = 'Document'
            AND record_id IN (#{quote(old_id)}, #{quote(old_id.to_i)})
        SQL
      end
    end

    remove_foreign_key :documents, :categories if foreign_key_exists?(:documents, :categories)
    remove_foreign_key :documents, :users if foreign_key_exists?(:documents, :users)

    drop_table :documents
    rename_table :documents_new, :documents

    add_foreign_key :documents, :categories
    add_foreign_key :documents, :users
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def quote(value)
    connection.quote(value)
  end
end
