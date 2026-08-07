# frozen_string_literal: true

class RequireDocumentsUserId < ActiveRecord::Migration[8.1]
  def up
    owner_id = User.where(admin: true).order(:id).limit(1).pick(:id) ||
               User.order(:id).limit(1).pick(:id)

    if owner_id
      execute(sanitize_sql_array([ "UPDATE documents SET user_id = ? WHERE user_id IS NULL", owner_id ]))
    elsif Document.where(user_id: nil).exists?
      raise ActiveRecord::IrreversibleMigration,
            "Cannot require documents.user_id: orphan documents exist and there is no user to own them"
    end

    change_column_null :documents, :user_id, false
  end

  def down
    change_column_null :documents, :user_id, true
  end

  private

  def sanitize_sql_array(array)
    ActiveRecord::Base.sanitize_sql_array(array)
  end
end
