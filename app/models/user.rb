class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :jwt_authenticatable, jwt_revocation_strategy: self

  has_many :expenses
  has_many :categories
end
