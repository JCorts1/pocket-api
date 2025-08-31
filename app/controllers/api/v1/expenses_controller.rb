require 'csv'

class Api::V1::ExpensesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_expense, only: [:update, :destroy]

  # GET /api/v1/expenses
  def index
    expenses = current_user.expenses

    # Check if start_date and end_date parameters were sent in the request.
    if params[:start_date].present? && params[:end_date].present?
      # If they exist, parse them into Date objects.
      start_date = Date.parse(params[:start_date])
      end_date = Date.parse(params[:end_date])

      @expenses = expenses.where(created_at: start_date.beginning_of_day..end_date.end_of_day)
    else
      # If no date range is provided, default to fetching expenses for the current month.
      @expenses = expenses.where(created_at: Time.now.all_month)
    end

    @expenses = @expenses.includes(:category).order(created_at: :desc)

    render json: @expenses, include: :category
  end

  # POST /api/v1/expenses
  def create
    @expense = current_user.expenses.build(expense_params)
    if @expense.save
      render json: @expense.to_json(include: :category), status: :created
    else
      render json: @expense.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/v1/expenses/:id
  def update
    if @expense.update(expense_params)
      render json: @expense.to_json(include: :category)
    else
      render json: @expense.errors, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/expenses/:id
  def destroy
    @expense.destroy
    head :no_content
  end

  # GET /api/v1/expenses/export_csv
  def export_csv
    year = params[:year]&.to_i || Date.current.year
    
    # Get all expenses and incomes for the specified year
    expenses = current_user.expenses
      .includes(:category)
      .where(created_at: Date.new(year).beginning_of_year..Date.new(year).end_of_year)
      .order(:created_at)
    
    incomes = current_user.incomes
      .where(created_at: Date.new(year).beginning_of_year..Date.new(year).end_of_year)
      .order(:created_at)

    # Generate CSV
    csv_data = generate_yearly_csv(expenses, incomes, year)
    
    # Return JSON response with CSV data for frontend to handle download
    render json: { 
      csv_data: csv_data,
      filename: "financial_report_#{year}.csv"
    }
  end

  private

  def set_expense
    @expense = current_user.expenses.find(params[:id])
  end

  def expense_params
    params.require(:expense).permit(:amount, :description, :category_id)
  end

  def generate_yearly_csv(expenses, incomes, year)
    # Initialize monthly summaries
    monthly_data = (1..12).map do |month|
      {
        month: Date::MONTHNAMES[month],
        month_number: month,
        total_income: 0.0,
        total_expenses: 0.0,
        net_balance: 0.0,
        expense_categories: Hash.new(0.0)
      }
    end

    # Process expenses
    expenses.each do |expense|
      month_index = expense.created_at.month - 1
      monthly_data[month_index][:total_expenses] += expense.amount.to_f
      category_name = expense.category.name
      monthly_data[month_index][:expense_categories][category_name] += expense.amount.to_f
    end

    # Process incomes
    incomes.each do |income|
      month_index = income.created_at.month - 1
      monthly_data[month_index][:total_income] += income.amount.to_f
    end

    # Calculate net balance for each month
    monthly_data.each do |month_data|
      month_data[:net_balance] = month_data[:total_income] - month_data[:total_expenses]
    end

    # Generate CSV
    CSV.generate do |csv|
      # Header with report info
      csv << ["Financial Report - Year #{year}"]
      csv << ["Generated on: #{Date.current.strftime('%B %d, %Y')}"]
      csv << []

      # Monthly summary header
      csv << ["MONTHLY SUMMARY"]
      csv << ["Month", "Total Income", "Total Expenses", "Net Balance"]
      
      # Monthly summary data
      monthly_data.each do |month_data|
        csv << [
          month_data[:month],
          "$#{sprintf('%.2f', month_data[:total_income])}",
          "$#{sprintf('%.2f', month_data[:total_expenses])}",
          "$#{sprintf('%.2f', month_data[:net_balance])}"
        ]
      end

      # Year totals
      total_income = monthly_data.sum { |m| m[:total_income] }
      total_expenses = monthly_data.sum { |m| m[:total_expenses] }
      total_net = total_income - total_expenses
      
      csv << []
      csv << ["YEARLY TOTALS"]
      csv << ["Total Income", "Total Expenses", "Net Balance"]
      csv << [
        "$#{sprintf('%.2f', total_income)}",
        "$#{sprintf('%.2f', total_expenses)}",
        "$#{sprintf('%.2f', total_net)}"
      ]

      # Category breakdown
      csv << []
      csv << ["EXPENSES BY CATEGORY (Monthly Breakdown)"]
      
      # Get all unique categories
      all_categories = monthly_data.flat_map { |m| m[:expense_categories].keys }.uniq.sort
      
      if all_categories.any?
        # Category headers
        csv << ["Month"] + all_categories + ["Monthly Total"]
        
        # Category data for each month
        monthly_data.each do |month_data|
          row = [month_data[:month]]
          all_categories.each do |category|
            amount = month_data[:expense_categories][category]
            row << "$#{sprintf('%.2f', amount)}"
          end
          row << "$#{sprintf('%.2f', month_data[:total_expenses])}"
          csv << row
        end
        
        # Category totals
        csv << ["TOTAL"] + all_categories.map { |cat|
          total = monthly_data.sum { |m| m[:expense_categories][cat] }
          "$#{sprintf('%.2f', total)}"
        } + ["$#{sprintf('%.2f', total_expenses)}"]
      end

      # Individual transactions
      csv << []
      csv << ["DETAILED TRANSACTIONS"]
      csv << ["Date", "Type", "Description", "Category", "Amount"]
      
      # Combine and sort all transactions
      all_transactions = []
      
      expenses.each do |expense|
        all_transactions << {
          date: expense.created_at,
          type: "Expense",
          description: expense.description || "No description",
          category: expense.category.name,
          amount: -expense.amount.to_f
        }
      end
      
      incomes.each do |income|
        all_transactions << {
          date: income.created_at,
          type: "Income",
          description: income.description || "Income",
          category: "Income",
          amount: income.amount.to_f
        }
      end
      
      all_transactions.sort_by { |t| t[:date] }.each do |transaction|
        csv << [
          transaction[:date].strftime("%Y-%m-%d"),
          transaction[:type],
          transaction[:description],
          transaction[:category],
          "$#{sprintf('%.2f', transaction[:amount].abs)}"
        ]
      end
    end
  end
end
