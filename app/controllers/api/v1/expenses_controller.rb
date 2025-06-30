class Api::V1::ExpensesController < ApplicationController
  before_action :authenticate_user! # Devise's helper to ensure user is logged in
  before_action :set_expense, only: [:update, :destroy]

  # GET /api/v1/expenses
  def index
    # The .includes(:category) is a performance optimization. It fetches all
    # associated category data in one go, preventing a separate database query
    # for each individual expense, which is much faster.
    # The .all is not necessary when chaining other Active Record methods.
    @expenses = current_user.expenses.includes(:category).order(created_at: :desc)

    # Using the `include:` option is the more standard Rails way to handle this.
    render json: @expenses, include: :category
  end

  # POST /api/v1/expenses
  def create
    @expense = current_user.expenses.build(expense_params) # Build from current_user
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

  private

  def set_expense
    @expense = current_user.expenses.find(params[:id])
  end

  def expense_params
    params.require(:expense).permit(:amount, :description, :category_id)
  end
end
