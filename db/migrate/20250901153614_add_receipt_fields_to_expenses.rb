class AddReceiptFieldsToExpenses < ActiveRecord::Migration[7.1]
  def change
    add_column :expenses, :receipt_image_url, :string
    add_column :expenses, :ocr_confidence, :float
    add_column :expenses, :needs_review, :boolean, default: false
  end
end
