class Expense < ApplicationRecord
  belongs_to :category
  belongs_to :user
  
  has_one_attached :receipt_image
  
  validates :amount, presence: true, numericality: { greater_than: 0 }
end
