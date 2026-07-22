# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_21_152403) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "categories", force: :cascade do |t|
    t.boolean "auto_create", default: true, null: false
    t.string "color", default: "#6366f1"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "directory_path", null: false
    t.text "keywords"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_categories_on_slug", unique: true
  end

  create_table "classification_rules", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "category_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "pattern", null: false
    t.integer "priority", default: 100, null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_classification_rules_on_category_id"
    t.index ["priority"], name: "index_classification_rules_on_priority"
  end

  create_table "documents", force: :cascade do |t|
    t.integer "byte_size"
    t.integer "category_id"
    t.datetime "classified_at"
    t.string "classifier_used"
    t.float "confidence"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.text "extracted_text"
    t.string "issuer"
    t.float "issuer_confidence"
    t.json "metadata", default: {}
    t.string "original_filename", null: false
    t.string "relative_path"
    t.string "source", default: "web", null: false
    t.string "status", default: "pending", null: false
    t.text "summary"
    t.text "tags"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_documents_on_category_id"
    t.index ["issuer"], name: "index_documents_on_issuer"
    t.index ["original_filename"], name: "index_documents_on_original_filename"
    t.index ["source"], name: "index_documents_on_source"
    t.index ["status"], name: "index_documents_on_status"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "classification_rules", "categories"
  add_foreign_key "documents", "categories"
end
