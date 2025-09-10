class ExpensePredictionService
  def initialize(user)
    @user = user
  end

  # Predict monthly spending based on historical data and recurring expenses
  def predict_monthly_spending(target_month = Date.current.month, target_year = Date.current.year)
    {
      predicted_total: calculate_predicted_total(target_month, target_year),
      category_predictions: predict_by_category(target_month, target_year),
      recurring_expenses: calculate_recurring_impact(target_month, target_year),
      historical_average: calculate_historical_average,
      confidence_score: calculate_confidence_score
    }
  end

  # Predict spending for next month based on current trends
  def predict_next_month
    next_month = Date.current.next_month
    predict_monthly_spending(next_month.month, next_month.year)
  end

  # Get spending trends over the last 6 months
  def spending_trends(months = 6)
    end_date = Date.current.end_of_month
    start_date = end_date - months.months + 1.day
    
    trends = []
    
    (0...months).each do |i|
      month_date = start_date + i.months
      month_start = month_date.beginning_of_month
      month_end = month_date.end_of_month
      
      total = @user.expenses
                  .where(created_at: month_start..month_end)
                  .sum(:amount)
      
      trends << {
        month: month_date.strftime('%B %Y'),
        month_short: month_date.strftime('%b %y'),
        total: total.to_f,
        date: month_date.strftime('%Y-%m')
      }
    end
    
    trends
  end

  # Identify unusual spending patterns
  def detect_spending_anomalies
    historical_data = spending_trends(12)
    return [] if historical_data.length < 3
    
    amounts = historical_data.map { |d| d[:total] }
    mean = amounts.sum / amounts.length
    std_dev = Math.sqrt(amounts.map { |x| (x - mean) ** 2 }.sum / amounts.length)
    
    anomalies = []
    historical_data.each do |month_data|
      z_score = (month_data[:total] - mean) / std_dev
      if z_score.abs > 2 # More than 2 standard deviations
        anomalies << {
          month: month_data[:month],
          amount: month_data[:total],
          deviation: z_score > 0 ? 'high' : 'low',
          z_score: z_score.round(2)
        }
      end
    end
    
    anomalies
  end

  private

  def calculate_predicted_total(target_month, target_year)
    # Get historical average for the same month across previous years
    historical_same_month = calculate_historical_same_month(target_month)
    
    # Get overall historical average
    overall_average = calculate_historical_average
    
    # Get recurring expenses for the month
    recurring_impact = calculate_recurring_impact(target_month, target_year)
    
    # Weight the prediction: 40% same month history, 40% overall average, 20% trending
    current_month_trend = calculate_current_trend
    
    prediction = (historical_same_month * 0.4 + 
                 overall_average * 0.4 + 
                 current_month_trend * 0.2 +
                 recurring_impact).round(2)
    
    [prediction, 0].max # Never predict negative spending
  end

  def predict_by_category(target_month, target_year)
    categories = @user.expenses.joins(:category).distinct.pluck('categories.id', 'categories.name')
    
    predictions = categories.map do |category_id, category_name|
      # Historical average for this category
      historical_avg = @user.expenses
                           .joins(:category)
                           .where(categories: { id: category_id })
                           .where('created_at >= ?', 6.months.ago)
                           .group("DATE_TRUNC('month', created_at)")
                           .sum(:amount)
                           .values
                           .sum / 6.0
      
      # Recurring expenses for this category
      recurring = @user.recurring_expenses
                      .active
                      .joins(:category)
                      .where(categories: { id: category_id })
                      .sum(&:monthly_impact)
      
      predicted_amount = (historical_avg + recurring).round(2)
      
      {
        category_id: category_id,
        category_name: category_name,
        predicted_amount: predicted_amount,
        historical_average: historical_avg.round(2),
        recurring_contribution: recurring.round(2)
      }
    end
    
    predictions.select { |p| p[:predicted_amount] > 0 }
  end

  def calculate_recurring_impact(target_month, target_year)
    # Sum up all active recurring expenses that would occur in the target month
    target_date = Date.new(target_year, target_month, 1)
    month_range = target_date.beginning_of_month..target_date.end_of_month
    
    total_recurring = 0
    
    @user.recurring_expenses.active.find_each do |recurring|
      # Count how many times this recurring expense would occur in the month
      occurrences = count_occurrences_in_month(recurring, target_month, target_year)
      total_recurring += recurring.amount * occurrences
    end
    
    total_recurring.round(2)
  end

  def count_occurrences_in_month(recurring, target_month, target_year)
    target_date = Date.new(target_year, target_month, 1)
    month_start = target_date.beginning_of_month
    month_end = target_date.end_of_month
    
    return 0 if recurring.next_due_date > month_end
    
    frequency_days = RecurringExpense::FREQUENCIES[recurring.frequency]
    occurrences = 0
    current_date = [recurring.next_due_date, month_start].max
    
    while current_date <= month_end
      occurrences += 1
      current_date += frequency_days.days
    end
    
    occurrences
  end

  def calculate_historical_average
    @user.expenses
         .where('created_at >= ?', 6.months.ago)
         .group("DATE_TRUNC('month', created_at)")
         .sum(:amount)
         .values
         .then { |totals| totals.empty? ? 0 : totals.sum / totals.length.to_f }
         .round(2)
  end

  def calculate_historical_same_month(target_month)
    # Get spending for the same month in previous years
    same_month_totals = []
    
    (1..3).each do |years_back|
      year = Date.current.year - years_back
      month_start = Date.new(year, target_month, 1).beginning_of_month
      month_end = Date.new(year, target_month, 1).end_of_month
      
      total = @user.expenses
                  .where(created_at: month_start..month_end)
                  .sum(:amount)
      
      same_month_totals << total if total > 0
    end
    
    same_month_totals.empty? ? calculate_historical_average : (same_month_totals.sum / same_month_totals.length.to_f)
  end

  def calculate_current_trend
    # Calculate trend based on last 3 months vs previous 3 months
    last_3_months = @user.expenses
                        .where('created_at >= ?', 3.months.ago)
                        .sum(:amount) / 3.0
    
    previous_3_months = @user.expenses
                            .where(created_at: 6.months.ago..3.months.ago)
                            .sum(:amount) / 3.0
    
    return last_3_months if previous_3_months == 0
    
    # Apply trend to last 3 months average
    trend_factor = last_3_months / previous_3_months
    (last_3_months * trend_factor).round(2)
  end

  def calculate_confidence_score
    # Base confidence on amount of historical data
    months_of_data = @user.expenses
                         .group("DATE_TRUNC('month', created_at)")
                         .count
                         .keys
                         .length
    
    case months_of_data
    when 0..1
      25
    when 2..3
      50
    when 4..6
      75
    when 7..12
      85
    else
      95
    end
  end
end