class Category < ApplicationRecord
  has_many :expenses
  belongs_to :user, optional: true
end
