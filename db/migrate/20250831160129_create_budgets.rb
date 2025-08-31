class CreateBudgets < ActiveRecord::Migration[7.1]
  def change
    create_table :budgets do |t|
      t.references :user, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.decimal :monthly_limit, precision: 10, scale: 2, null: false
      t.integer :month, null: false
      t.integer :year, null: false

      t.timestamps
    end

    add_index :budgets, [:user_id, :category_id, :month, :year], unique: true, name: 'index_budgets_on_user_category_month_year'
  end
end
