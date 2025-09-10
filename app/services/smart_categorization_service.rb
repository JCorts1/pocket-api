class SmartCategorizationService
  def initialize(user)
    @user = user
  end

  # Suggest categories for a new expense based on description
  def suggest_categories(description, amount = nil)
    return [] if description.blank?
    
    # Clean and normalize the description
    normalized_description = normalize_description(description)
    
    suggestions = []
    
    # 1. Exact description match
    exact_matches = find_exact_matches(normalized_description)
    suggestions.concat(exact_matches)
    
    # 2. Partial description matches
    partial_matches = find_partial_matches(normalized_description)
    suggestions.concat(partial_matches)
    
    # 3. Keyword-based matches
    keyword_matches = find_keyword_matches(normalized_description)
    suggestions.concat(keyword_matches)
    
    # 4. Amount-based suggestions
    if amount
      amount_matches = find_amount_based_matches(amount.to_f)
      suggestions.concat(amount_matches)
    end
    
    # 5. Fallback to default category patterns
    default_matches = find_default_patterns(normalized_description)
    suggestions.concat(default_matches)
    
    # Deduplicate, sort by confidence, and return top 3
    unique_suggestions = deduplicate_suggestions(suggestions)
    unique_suggestions.sort_by { |s| -s[:confidence] }.first(3)
  end

  # Analyze user's categorization patterns
  def analyze_patterns
    patterns = {
      most_used_categories: most_used_categories,
      category_keywords: extract_category_keywords,
      amount_ranges: analyze_amount_ranges,
      time_patterns: analyze_time_patterns
    }
    
    patterns
  end

  # Detect potential miscategorizations
  def detect_miscategorizations(limit = 20)
    suspicious_expenses = []
    
    @user.expenses.includes(:category).limit(limit * 3).find_each do |expense|
      suggestions = suggest_categories(expense.description, expense.amount)
      
      # If top suggestion has high confidence and differs from actual category
      if suggestions.any? && 
         suggestions.first[:confidence] > 80 && 
         suggestions.first[:category_id] != expense.category_id
        
        suspicious_expenses << {
          expense_id: expense.id,
          description: expense.description,
          amount: expense.amount,
          current_category: expense.category.name,
          current_category_id: expense.category_id,
          suggested_category: suggestions.first[:category_name],
          suggested_category_id: suggestions.first[:category_id],
          confidence: suggestions.first[:confidence],
          created_at: expense.created_at
        }
      end
    end
    
    suspicious_expenses.first(limit)
  end

  private

  def normalize_description(description)
    description.to_s.downcase.strip
               .gsub(/[^\w\s]/, ' ')  # Replace punctuation with spaces
               .squeeze(' ')          # Remove multiple spaces
  end

  def find_exact_matches(description)
    # Find expenses with exactly the same description
    matches = @user.expenses
                  .joins(:category)
                  .where('LOWER(expenses.description) = ?', description)
                  .group('categories.id', 'categories.name')
                  .count
    
    matches.map do |category_info, count|
      category_id, category_name = category_info
      {
        category_id: category_id,
        category_name: category_name,
        confidence: calculate_confidence(count, 'exact'),
        reason: 'Exact description match',
        match_count: count
      }
    end
  end

  def find_partial_matches(description)
    words = description.split(' ').select { |w| w.length > 2 }
    return [] if words.empty?
    
    matches = {}
    
    words.each do |word|
      # Find expenses containing this word
      expense_matches = @user.expenses
                            .joins(:category)
                            .where('LOWER(expenses.description) LIKE ?', "%#{word}%")
                            .group('categories.id', 'categories.name')
                            .count
      
      expense_matches.each do |category_info, count|
        category_id, category_name = category_info
        key = "#{category_id}-#{category_name}"
        
        matches[key] ||= { 
          category_id: category_id, 
          category_name: category_name, 
          word_matches: [], 
          total_count: 0 
        }
        matches[key][:word_matches] << word
        matches[key][:total_count] += count
      end
    end
    
    matches.values.map do |match|
      {
        category_id: match[:category_id],
        category_name: match[:category_name],
        confidence: calculate_confidence(match[:total_count], 'partial', match[:word_matches].length),
        reason: "Partial match: #{match[:word_matches].join(', ')}",
        match_count: match[:total_count]
      }
    end
  end

  def find_keyword_matches(description)
    keyword_patterns = {
      'Food & Dining' => ['restaurant', 'food', 'lunch', 'dinner', 'breakfast', 'coffee', 'pizza', 'burger', 'cafe', 'bistro', 'delivery'],
      'Transportation' => ['gas', 'fuel', 'uber', 'lyft', 'taxi', 'bus', 'train', 'parking', 'toll', 'car', 'metro'],
      'Shopping' => ['amazon', 'store', 'mall', 'purchase', 'buy', 'shop', 'retail', 'walmart', 'target'],
      'Entertainment' => ['movie', 'cinema', 'concert', 'show', 'netflix', 'spotify', 'game', 'theater', 'entertainment'],
      'Utilities' => ['electric', 'water', 'gas', 'internet', 'phone', 'cable', 'utility', 'bill'],
      'Healthcare' => ['doctor', 'hospital', 'pharmacy', 'medicine', 'dental', 'medical', 'health', 'clinic'],
      'Groceries' => ['grocery', 'supermarket', 'groceries', 'market', 'whole foods', 'trader joes', 'safeway'],
      'Travel' => ['hotel', 'flight', 'airline', 'booking', 'airbnb', 'vacation', 'trip', 'travel']
    }
    
    matches = []
    
    keyword_patterns.each do |category_name, keywords|
      matched_keywords = keywords.select { |keyword| description.include?(keyword) }
      
      if matched_keywords.any?
        # Try to find this category in user's existing categories
        category = @user.expenses.joins(:category)
                       .where('LOWER(categories.name) LIKE ?', "%#{category_name.downcase}%")
                       .first&.category
        
        if category
          confidence = 60 + (matched_keywords.length * 10) # Base 60% + 10% per keyword
          matches << {
            category_id: category.id,
            category_name: category.name,
            confidence: [confidence, 90].min, # Cap at 90%
            reason: "Keyword match: #{matched_keywords.join(', ')}",
            match_count: matched_keywords.length
          }
        end
      end
    end
    
    matches
  end

  def find_amount_based_matches(amount)
    # Find categories where user frequently spends similar amounts
    amount_range = (amount * 0.8)..(amount * 1.2) # ±20% range
    
    matches = @user.expenses
                  .joins(:category)
                  .where(amount: amount_range)
                  .group('categories.id', 'categories.name')
                  .count
    
    total_similar_amount_expenses = matches.values.sum
    
    matches.map do |category_info, count|
      category_id, category_name = category_info
      percentage = (count.to_f / total_similar_amount_expenses * 100).round(1)
      
      {
        category_id: category_id,
        category_name: category_name,
        confidence: [percentage, 70].min, # Cap at 70% for amount-based matching
        reason: "Similar amount pattern ($#{amount})",
        match_count: count
      }
    end.select { |match| match[:confidence] > 20 } # Only include if >20% of similar amounts
  end

  def find_default_patterns(description)
    # Fallback patterns for common expense types
    default_patterns = [
      { pattern: /grocery|food|market/, category_name: 'Groceries', confidence: 40 },
      { pattern: /gas|fuel/, category_name: 'Transportation', confidence: 45 },
      { pattern: /restaurant|dining/, category_name: 'Food & Dining', confidence: 45 },
      { pattern: /amazon|shopping/, category_name: 'Shopping', confidence: 40 },
      { pattern: /coffee/, category_name: 'Food & Dining', confidence: 50 }
    ]
    
    matches = []
    
    default_patterns.each do |pattern_info|
      if description.match?(pattern_info[:pattern])
        # Try to find a category with similar name
        category = @user.expenses.joins(:category)
                       .where('LOWER(categories.name) LIKE ?', "%#{pattern_info[:category_name].downcase}%")
                       .first&.category
        
        # If no similar category, suggest the most used category
        category ||= most_used_categories.first&.dig(:category)
        
        if category
          matches << {
            category_id: category.id,
            category_name: category.name,
            confidence: pattern_info[:confidence],
            reason: 'Default pattern match',
            match_count: 0
          }
        end
      end
    end
    
    matches
  end

  def calculate_confidence(count, match_type, extra_factor = 1)
    base_confidence = case match_type
                     when 'exact'
                       80 + (count * 5)
                     when 'partial'
                       50 + (count * 3) + (extra_factor * 5)
                     else
                       30 + (count * 2)
                     end
    
    [base_confidence, 95].min # Cap at 95%
  end

  def deduplicate_suggestions(suggestions)
    # Group by category_id and take the one with highest confidence
    suggestions.group_by { |s| s[:category_id] }
               .map { |_, group| group.max_by { |s| s[:confidence] } }
  end

  def most_used_categories
    @user.expenses
         .joins(:category)
         .group('categories.id', 'categories.name')
         .count
         .map { |category_info, count| 
           category_id, category_name = category_info
           { 
             category_id: category_id, 
             category_name: category_name, 
             usage_count: count,
             category: @user.expenses.joins(:category).where('categories.id = ?', category_id).first.category
           } 
         }
         .sort_by { |c| -c[:usage_count] }
         .first(5)
  end

  def extract_category_keywords
    category_keywords = {}
    
    @user.expenses.joins(:category).find_each do |expense|
      category_name = expense.category.name
      category_keywords[category_name] ||= Hash.new(0)
      
      words = normalize_description(expense.description).split(' ')
      words.each { |word| category_keywords[category_name][word] += 1 if word.length > 2 }
    end
    
    # Keep only most frequent keywords per category
    category_keywords.transform_values do |keywords|
      keywords.sort_by { |_, count| -count }.first(5).to_h
    end
  end

  def analyze_amount_ranges
    @user.expenses
         .joins(:category)
         .group('categories.name')
         .group("CASE 
                 WHEN amount < 10 THEN 'Under $10'
                 WHEN amount < 50 THEN '$10-$50'
                 WHEN amount < 100 THEN '$50-$100'
                 WHEN amount < 500 THEN '$100-$500'
                 ELSE 'Over $500'
                 END")
         .count
  end

  def analyze_time_patterns
    {
      by_day_of_week: @user.expenses.joins(:category)
                          .group('categories.name')
                          .group("EXTRACT(DOW FROM created_at)")
                          .count,
      by_hour: @user.expenses.joins(:category)
                   .group('categories.name')
                   .group("EXTRACT(HOUR FROM created_at)")
                   .count
    }
  end
end