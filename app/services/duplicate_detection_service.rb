class DuplicateDetectionService
  def initialize(user)
    @user = user
  end

  # Check for potential duplicates of a new expense
  def check_for_duplicates(description, amount, category_id = nil, created_at = nil)
    return { has_duplicates: false, duplicates: [] } if description.blank? || amount.blank?
    
    amount = amount.to_f
    created_at = created_at&.to_date || Date.current
    
    # Search for similar expenses within the last 7 days
    search_start = created_at - 7.days
    search_end = created_at + 1.day
    
    potential_duplicates = @user.expenses
                               .where(created_at: search_start..search_end)
                               .where.not(id: nil) # Placeholder for excluding current expense if updating
    
    duplicates = []
    
    potential_duplicates.find_each do |expense|
      similarity_score = calculate_similarity_score(
        description, expense.description,
        amount, expense.amount,
        category_id, expense.category_id,
        created_at, expense.created_at.to_date
      )
      
      if similarity_score >= 80 # High confidence duplicate
        duplicates << {
          expense_id: expense.id,
          description: expense.description,
          amount: expense.amount.to_f,
          category_name: expense.category.name,
          created_at: expense.created_at,
          similarity_score: similarity_score,
          duplicate_type: determine_duplicate_type(similarity_score)
        }
      end
    end
    
    # Sort by similarity score descending
    duplicates.sort_by! { |d| -d[:similarity_score] }
    
    {
      has_duplicates: duplicates.any?,
      duplicate_count: duplicates.length,
      duplicates: duplicates.first(5), # Limit to top 5 matches
      confidence: duplicates.any? ? duplicates.first[:similarity_score] : 0
    }
  end

  # Find all potential duplicates in user's expenses
  def find_all_duplicates(limit = 50)
    duplicate_groups = []
    processed_ids = Set.new
    
    @user.expenses.includes(:category)
         .order(created_at: :desc)
         .limit(limit * 2)
         .find_each do |expense|
      
      next if processed_ids.include?(expense.id)
      
      # Find similar expenses
      similar_expenses = find_similar_expenses(expense)
      
      if similar_expenses.any?
        # Mark all as processed
        expense_group = [expense] + similar_expenses
        expense_group.each { |e| processed_ids << e.id }
        
        # Create duplicate group
        duplicate_groups << {
          primary_expense: format_expense_for_duplicates(expense),
          similar_expenses: similar_expenses.map { |e| format_expense_for_duplicates(e) },
          group_size: expense_group.size,
          total_amount: expense_group.sum(&:amount).to_f,
          date_range: {
            earliest: expense_group.map(&:created_at).min,
            latest: expense_group.map(&:created_at).max
          }
        }
      end
    end
    
    duplicate_groups.first(limit)
  end

  # Merge duplicate expenses (keep the first one, delete others)
  def merge_duplicates(primary_expense_id, duplicate_expense_ids)
    primary_expense = @user.expenses.find(primary_expense_id)
    duplicate_expenses = @user.expenses.where(id: duplicate_expense_ids)
    
    return { error: 'Primary expense not found' } unless primary_expense
    return { error: 'No duplicate expenses found' } if duplicate_expenses.empty?
    
    merged_info = {
      primary_expense: format_expense_for_duplicates(primary_expense),
      deleted_expenses: duplicate_expenses.map { |e| format_expense_for_duplicates(e) },
      total_amount_removed: duplicate_expenses.sum(:amount).to_f
    }
    
    # Delete the duplicate expenses
    duplicate_expenses.destroy_all
    
    {
      success: true,
      merged_info: merged_info,
      message: "Merged #{duplicate_expense_ids.length} duplicate expenses"
    }
  end

  # Auto-detect and suggest merges for obvious duplicates
  def suggest_auto_merges
    suggestions = []
    
    find_all_duplicates(30).each do |group|
      primary = group[:primary_expense]
      similar = group[:similar_expenses]
      
      # Only suggest if we have high confidence matches
      high_confidence_duplicates = similar.select { |s| s[:similarity_score] >= 90 }
      
      if high_confidence_duplicates.any?
        suggestions << {
          primary_expense_id: primary[:expense_id],
          duplicate_expense_ids: high_confidence_duplicates.map { |s| s[:expense_id] },
          confidence: high_confidence_duplicates.map { |s| s[:similarity_score] }.max,
          potential_savings: high_confidence_duplicates.sum { |s| s[:amount] },
          reason: determine_merge_reason(primary, high_confidence_duplicates)
        }
      end
    end
    
    suggestions.sort_by { |s| -s[:confidence] }.first(10)
  end

  private

  def calculate_similarity_score(desc1, desc2, amount1, amount2, cat1, cat2, date1, date2)
    # Description similarity (40% weight)
    desc_similarity = description_similarity(desc1, desc2) * 0.4
    
    # Amount similarity (35% weight) 
    amount_similarity = amount_similarity(amount1, amount2) * 0.35
    
    # Category similarity (15% weight)
    category_similarity = category_similarity(cat1, cat2) * 0.15
    
    # Date proximity (10% weight)
    date_similarity = date_proximity_score(date1, date2) * 0.10
    
    total_score = desc_similarity + amount_similarity + category_similarity + date_similarity
    total_score.round(1)
  end

  def description_similarity(desc1, desc2)
    return 100 if desc1.to_s.downcase == desc2.to_s.downcase
    
    # Clean descriptions
    clean1 = normalize_description(desc1)
    clean2 = normalize_description(desc2)
    
    return 100 if clean1 == clean2
    
    # Calculate word overlap
    words1 = clean1.split(' ')
    words2 = clean2.split(' ')
    
    return 0 if words1.empty? || words2.empty?
    
    common_words = words1 & words2
    total_words = (words1 + words2).uniq.length
    
    (common_words.length.to_f / total_words * 100).round(1)
  end

  def amount_similarity(amount1, amount2)
    return 0 if amount1 == 0 && amount2 == 0
    
    diff = (amount1 - amount2).abs
    avg = (amount1 + amount2) / 2.0
    
    return 100 if diff == 0
    return 0 if avg == 0
    
    # Exact match = 100%, within 1% = 95%, within 5% = 80%, etc.
    percentage_diff = (diff / avg) * 100
    
    case percentage_diff
    when 0
      100
    when 0..1
      95
    when 1..5
      80
    when 5..10
      60
    when 10..20
      40
    else
      0
    end
  end

  def category_similarity(cat1, cat2)
    return 100 if cat1 && cat2 && cat1 == cat2
    return 50 if cat1.nil? || cat2.nil? # One missing category
    return 0 # Different categories
  end

  def date_proximity_score(date1, date2)
    diff_days = (date1 - date2).abs.to_i
    
    case diff_days
    when 0
      100 # Same day
    when 1
      80  # Next day
    when 2..3
      60  # Within 3 days
    when 4..7
      30  # Within a week
    else
      0   # More than a week
    end
  end

  def normalize_description(description)
    description.to_s.downcase.strip
               .gsub(/[^\w\s]/, ' ')
               .squeeze(' ')
               .strip
  end

  def determine_duplicate_type(score)
    case score
    when 95..100
      'exact_match'
    when 85..94
      'near_exact'
    when 80..84
      'likely_duplicate'
    else
      'possible_duplicate'
    end
  end

  def find_similar_expenses(expense)
    # Look for expenses in a 7-day window
    start_date = expense.created_at - 7.days
    end_date = expense.created_at + 7.days
    
    candidates = @user.expenses
                     .where.not(id: expense.id)
                     .where(created_at: start_date..end_date)
                     .includes(:category)
    
    similar = []
    
    candidates.find_each do |candidate|
      similarity = calculate_similarity_score(
        expense.description, candidate.description,
        expense.amount, candidate.amount,
        expense.category_id, candidate.category_id,
        expense.created_at.to_date, candidate.created_at.to_date
      )
      
      if similarity >= 80
        similar << candidate
      end
    end
    
    similar
  end

  def format_expense_for_duplicates(expense)
    {
      expense_id: expense.id,
      description: expense.description,
      amount: expense.amount.to_f,
      category_name: expense.category.name,
      category_id: expense.category_id,
      created_at: expense.created_at,
      similarity_score: 100 # Will be overridden for similar expenses
    }
  end

  def determine_merge_reason(primary, duplicates)
    if duplicates.all? { |d| d[:description] == primary[:description] }
      "Exact description matches"
    elsif duplicates.all? { |d| (d[:amount] - primary[:amount]).abs < 0.01 }
      "Exact amount matches"
    else
      "High similarity across multiple factors"
    end
  end
end