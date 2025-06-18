class CreateExpenses < ActiveRecord::Migration[7.1]
  def change
    create_table :expenses do |t|
      t.decimal :amount
      t.text :description
      t.references :category, null: false, foreign_key: true

      t.timestamps
    end
  end
end
