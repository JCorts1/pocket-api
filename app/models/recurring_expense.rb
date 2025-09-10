class RecurringExpense < ApplicationRecord
  belongs_to :user
  belongs_to :category
  
  FREQUENCIES = {
    'weekly' => 7,
    'bi_weekly' => 14,
    'monthly' => 30,
    'quarterly' => 90,
    'yearly' => 365
  }.freeze
  
  validates :description, presence: true, length: { minimum: 2, maximum: 255 }
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :frequency, presence: true, inclusion: { in: FREQUENCIES.keys }
  validates :start_date, :next_due_date, presence: true
  validates :end_date, comparison: { greater_than: :start_date }, allow_blank: true
  
  scope :active, -> { where(is_active: true) }
  scope :due_today, -> { active.where(next_due_date: Date.current) }
  scope :overdue, -> { active.where('next_due_date < ?', Date.current) }
  scope :upcoming, ->(days = 7) { active.where(next_due_date: Date.current..Date.current + days.days) }
  
  # Generate the next expense and update next_due_date
  def generate_expense!
    return unless should_generate?
    
    expense = user.expenses.create!(
      category: category,
      description: description,
      amount: amount,
      created_at: next_due_date
    )
    
    update_next_due_date!
    expense
  end
  
  # Check if this recurring expense should generate a new expense
  def should_generate?
    is_active && next_due_date <= Date.current && !past_end_date?
  end
  
  # Calculate the next due date based on frequency
  def calculate_next_due_date
    days_to_add = FREQUENCIES[frequency]
    next_due_date + days_to_add.days
  end
  
  # Update the next due date
  def update_next_due_date!
    new_date = calculate_next_due_date
    
    # If there's an end_date and new_date exceeds it, deactivate
    if end_date && new_date > end_date
      update!(is_active: false)
    else
      update!(next_due_date: new_date)
    end
  end
  
  # Check if recurring expense is past its end date
  def past_end_date?
    end_date && next_due_date > end_date
  end
  
  # Get frequency in human readable format
  def frequency_label
    frequency.humanize
  end
  
  # Estimate monthly impact
  def monthly_impact
    case frequency
    when 'weekly'
      amount * 4.33 # Average weeks per month
    when 'bi_weekly'
      amount * 2.17 # Average bi-weeks per month
    when 'monthly'
      amount
    when 'quarterly'
      amount / 3
    when 'yearly'
      amount / 12
    else
      0
    end
  end
end
