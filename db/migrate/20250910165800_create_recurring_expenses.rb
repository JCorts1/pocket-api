class CreateRecurringExpenses < ActiveRecord::Migration[7.1]
  def change
    create_table :recurring_expenses do |t|
      t.references :user, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.string :description, null: false
      t.decimal :amount, precision: 8, scale: 2, null: false
      t.string :frequency, null: false
      t.date :next_due_date, null: false
      t.boolean :is_active, default: true
      t.date :start_date, null: false
      t.date :end_date

      t.timestamps
    end
    
    add_index :recurring_expenses, [:user_id, :is_active]
    add_index :recurring_expenses, :next_due_date
  end
end
