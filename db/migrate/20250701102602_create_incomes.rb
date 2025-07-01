class CreateIncomes < ActiveRecord::Migration[7.1]
  def change
    create_table :incomes do |t|
      t.decimal :amount
      t.text :description
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
