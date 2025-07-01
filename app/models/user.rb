# app/models/user.rb
class User < ApplicationRecord
  # Add this line
  include Devise::JWT::RevocationStrategies::JTIMatcher

  devise :database_authenticatable, :registerable,
         :jwt_authenticatable, jwt_revocation_strategy: self

  has_many :expenses
  has_many :categories
  has_many :incomes
end
