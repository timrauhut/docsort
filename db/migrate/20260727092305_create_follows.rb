class CreateFollows < ActiveRecord::Migration[8.1]
  def change
    create_table :follows do |t|
      t.references :follower, null: false, foreign_key: { to_table: :users }, index: true
      t.references :followed, null: false, foreign_key: { to_table: :users }, index: true

      t.timestamps
    end

    add_index :follows, %i[follower_id followed_id], unique: true
  end
end
