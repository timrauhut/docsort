class AddUserToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_reference :documents, :user, foreign_key: true
  end
end
