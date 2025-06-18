class Api::V1::ExpensesController < ApplicationController
  before_action :set_expense, only: [:update, :destroy]

  # GET /api/v1/expenses
  def index
    # You might want to filter expenses, e.g., by month
    @expenses = Expense.all.order(created_at: :desc)
    render json: @expenses.to_json(include: :category)
  end

  # POST /api/v1/expenses
  def create
    @expense = Expense.new(expense_params)
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

  def set_expense
    @expense = Expense.find(params[:id])
  end

  def expense_params
    # Ensure you permit category_id so the association can be made
    params.require(:expense).permit(:amount, :description, :category_id)
  end
end
