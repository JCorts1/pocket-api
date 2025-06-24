class AddJtiToUsers < ActiveRecord::Migration[7.1]
  def change
    # 1. Add the column but allow null values for now
    add_column :users, :jti, :string

    # 2. Go through existing users and give them a unique jti
    User.all.each do |user|
      user.update_column(:jti, SecureRandom.uuid)
    end

    # 3. Now that all rows have a jti, change the column to not allow nulls
    change_column_null :users, :jti, false

    # 4. Finally, add the unique index
    add_index :users, :jti, unique: true
  end
end
