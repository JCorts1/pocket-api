class Api::V1::RecurringExpensesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_recurring_expense, only: [:show, :update, :destroy, :generate]

  # GET /api/v1/recurring_expenses
  def index
    @recurring_expenses = current_user.recurring_expenses
                                     .includes(:category)
                                     .order(:next_due_date)
    
    # Filter by status if requested
    case params[:status]
    when 'active'
      @recurring_expenses = @recurring_expenses.active
    when 'overdue'
      @recurring_expenses = @recurring_expenses.overdue
    when 'upcoming'
      days = params[:days]&.to_i || 7
      @recurring_expenses = @recurring_expenses.upcoming(days)
    end
    
    render json: @recurring_expenses, include: :category
  end

  # GET /api/v1/recurring_expenses/:id
  def show
    render json: @recurring_expense, include: :category
  end

  # POST /api/v1/recurring_expenses
  def create
    @recurring_expense = current_user.recurring_expenses.build(recurring_expense_params)
    
    if @recurring_expense.save
      render json: @recurring_expense.to_json(include: :category), status: :created
    else
      render json: @recurring_expense.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/v1/recurring_expenses/:id
  def update
    if @recurring_expense.update(recurring_expense_params)
      render json: @recurring_expense.to_json(include: :category)
    else
      render json: @recurring_expense.errors, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/recurring_expenses/:id
  def destroy
    @recurring_expense.destroy
    head :no_content
  end

  # POST /api/v1/recurring_expenses/:id/generate
  def generate
    begin
      expense = @recurring_expense.generate_expense!
      if expense
        render json: { 
          message: 'Expense generated successfully',
          expense: expense.to_json(include: :category),
          recurring_expense: @recurring_expense.to_json(include: :category)
        }
      else
        render json: { message: 'No expense generated - not due or inactive' }, status: :unprocessable_entity
      end
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/recurring_expenses/dashboard
  def dashboard
    @active_count = current_user.recurring_expenses.active.count
    @overdue_count = current_user.recurring_expenses.overdue.count
    @upcoming = current_user.recurring_expenses.upcoming(7).includes(:category)
    @monthly_impact = current_user.recurring_expenses.active.sum(&:monthly_impact)
    
    render json: {
      active_count: @active_count,
      overdue_count: @overdue_count,
      upcoming: @upcoming.as_json(include: :category),
      monthly_impact: @monthly_impact.round(2)
    }
  end

  # POST /api/v1/recurring_expenses/process_due
  def process_due
    processed = []
    current_user.recurring_expenses.due_today.find_each do |recurring_expense|
      expense = recurring_expense.generate_expense!
      processed << expense if expense
    end
    
    render json: {
      message: "Processed #{processed.count} recurring expenses",
      expenses: processed.map { |e| e.as_json(include: :category) }
    }
  end

  private

  def set_recurring_expense
    @recurring_expense = current_user.recurring_expenses.find(params[:id])
  end

  def recurring_expense_params
    params.require(:recurring_expense).permit(
      :category_id, :description, :amount, :frequency, 
      :start_date, :end_date, :next_due_date, :is_active
    )
  end
end