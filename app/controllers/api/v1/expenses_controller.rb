class Api::V1::ExpensesController < ApplicationController
  before_action :authenticate_user! # Devise's helper to ensure user is logged in
  before_action :set_expense, only: [:update, :destroy]

  # GET /api/v1/expenses
  def index
    @expenses = current_user.expenses.all.order(created_at: :desc) # Scope to current_user
    render json: @expenses.to_json(include: :category)
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
    head :no_content # Returns a 204 No Content response
  end

  private

  # Make sure the set_expense finds from the current user's expenses for security
  def set_expense
    @expense = current_user.expenses.find(params[:id])
  end

  def expense_params
    # Ensure you permit category_id so the association can be made
    params.require(:expense).permit(:amount, :description, :category_id)
  end
end
