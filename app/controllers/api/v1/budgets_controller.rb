class Api::V1::BudgetsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_budget, only: [:show, :update, :destroy]

  # GET /api/v1/budgets
  def index
    month = params[:month]&.to_i || Date.current.month
    year = params[:year]&.to_i || Date.current.year
    
    budgets = current_user.budgets
      .joins(:category)
      .includes(:category)
      .for_month(month, year)
      .order('categories.name')

    result = []
    budgets.each do |budget|
      result << {
        id: budget.id,
        category: {
          id: budget.category.id,
          name: budget.category.name
        },
        monthly_limit: budget.monthly_limit,
        current_spending: budget.current_spending,
        spending_percentage: budget.spending_percentage,
        remaining_budget: budget.remaining_budget,
        budget_status: budget.budget_status,
        month: budget.month,
        year: budget.year,
        over_budget: budget.over_budget?,
        near_limit: budget.near_limit?
      }
    end
    
    render json: result
  end

  # GET /api/v1/budgets/1
  def show
    render json: {
      id: @budget.id,
      category: {
        id: @budget.category.id,
        name: @budget.category.name
      },
      monthly_limit: @budget.monthly_limit,
      current_spending: @budget.current_spending,
      spending_percentage: @budget.spending_percentage,
      remaining_budget: @budget.remaining_budget,
      budget_status: @budget.budget_status,
      month: @budget.month,
      year: @budget.year,
      over_budget: @budget.over_budget?,
      near_limit: @budget.near_limit?
    }
  end

  # POST /api/v1/budgets
  def create
    @budget = current_user.budgets.build(budget_params)

    if @budget.save
      @budget = current_user.budgets.includes(:category).find(@budget.id) # Reload with associations
      
      render json: {
        id: @budget.id,
        category: {
          id: @budget.category.id,
          name: @budget.category.name
        },
        monthly_limit: @budget.monthly_limit,
        current_spending: @budget.current_spending,
        spending_percentage: @budget.spending_percentage,
        remaining_budget: @budget.remaining_budget,
        budget_status: @budget.budget_status,
        month: @budget.month,
        year: @budget.year,
        over_budget: @budget.over_budget?,
        near_limit: @budget.near_limit?
      }, status: :created
    else
      render json: { 
        message: @budget.errors.full_messages.join(', '),
        errors: @budget.errors 
      }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/v1/budgets/1
  def update
    if @budget.update(budget_params)
      render json: {
        id: @budget.id,
        category: {
          id: @budget.category.id,
          name: @budget.category.name
        },
        monthly_limit: @budget.monthly_limit,
        current_spending: @budget.current_spending,
        spending_percentage: @budget.spending_percentage,
        remaining_budget: @budget.remaining_budget,
        budget_status: @budget.budget_status,
        month: @budget.month,
        year: @budget.year
      }
    else
      render json: @budget.errors, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/budgets/1
  def destroy
    @budget.destroy
    head :no_content
  end

  # GET /api/v1/budgets/dashboard
  def dashboard
    month = params[:month]&.to_i || Date.current.month
    year = params[:year]&.to_i || Date.current.year
    
    budgets = current_user.budgets
      .includes(:category)
      .for_month(month, year)

    total_budget = budgets.sum(&:monthly_limit)
    total_spending = budgets.sum(&:current_spending)
    
    alerts = budgets.select(&:near_limit?)
    
    render json: {
      total_budget: total_budget,
      total_spending: total_spending,
      remaining_budget: total_budget - total_spending,
      spending_percentage: total_budget > 0 ? (total_spending / total_budget * 100).round(1) : 0,
      budgets_count: budgets.count,
      alerts_count: alerts.count,
      budget_health: calculate_budget_health(budgets),
      alerts: alerts.map do |budget|
        {
          category_name: budget.category.name,
          spending_percentage: budget.spending_percentage,
          status: budget.budget_status
        }
      end
    }
  end

  private

  def set_budget
    @budget = current_user.budgets.find(params[:id])
  end

  def budget_params
    params.require(:budget).permit(:category_id, :monthly_limit, :month, :year)
  end

  def calculate_budget_health(budgets)
    return 'no_budgets' if budgets.empty?
    
    over_budget_count = budgets.count(&:over_budget?)
    critical_count = budgets.count { |b| b.budget_status == 'critical' }
    warning_count = budgets.count { |b| b.budget_status == 'warning' }
    
    if over_budget_count > 0
      'poor'
    elsif critical_count > budgets.count / 2
      'critical'
    elsif warning_count > budgets.count / 2
      'warning'
    else
      'excellent'
    end
  end
end