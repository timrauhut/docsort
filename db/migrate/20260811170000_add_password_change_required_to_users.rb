class AddPasswordChangeRequiredToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :password_change_required, :boolean, default: false, null: false
  end
end
