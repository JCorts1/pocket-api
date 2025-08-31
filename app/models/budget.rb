class Budget < ApplicationRecord
  belongs_to :user
  belongs_to :category

  validates :monthly_limit, presence: true, numericality: { greater_than: 0 }
  validates :month, presence: true, inclusion: { in: 1..12 }
  validates :year, presence: true, numericality: { greater_than: 2020 }
  validates :user_id, uniqueness: { scope: [:category_id, :month, :year], 
                                   message: "Budget already exists for this category and month" }

  scope :current_month, -> { where(month: Date.current.month, year: Date.current.year) }
  scope :for_month, ->(month, year) { where(month: month, year: year) }

  def current_spending
    start_date = Date.new(year, month, 1).beginning_of_month
    end_date = Date.new(year, month, 1).end_of_month
    
    user.expenses
        .joins(:category)
        .where(category: category)
        .where(created_at: start_date..end_date)
        .sum(:amount) || 0.0
  end

  def spending_percentage
    return 0.0 if monthly_limit.zero?
    (current_spending / monthly_limit * 100).round(1)
  end

  def remaining_budget
    monthly_limit - current_spending
  end

  def over_budget?
    current_spending > monthly_limit
  end

  def near_limit?(threshold = 80)
    spending_percentage >= threshold
  end

  def budget_status
    if over_budget?
      'over_budget'
    elsif near_limit?(90)
      'critical'
    elsif near_limit?(75)
      'warning'
    else
      'healthy'
    end
  end
end
