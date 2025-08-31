class Api::V1::IncomesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_income, only: [:update, :destroy]

  # GET /api/v1/incomes
  def index
    incomes = current_user.incomes

    # Check if start_date and end_date parameters were sent.
    if params[:start_date].present? && params[:end_date].present?
      start_date = Date.parse(params[:start_date])
      end_date = Date.parse(params[:end_date])

      @incomes = incomes.where(created_at: start_date.beginning_of_day..end_date.end_of_day)
    else
      @incomes = incomes.where(created_at: Time.now.all_month)
    end

    # The .order(created_at: :desc) shows the most recent incomes first.
    @incomes = @incomes.order(created_at: :desc)

    render json: @incomes
  end

  # POST /api/v1/incomes
  def create
    @income = current_user.incomes.build(income_params)
    if @income.save
      render json: @income, status: :created
    else
      render json: { error: @income.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/v1/incomes/:id
  def update
    if @income.update(income_params)
      render json: @income
    else
      render json: { error: @income.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/incomes/:id
  def destroy
    @income.destroy
    head :no_content
  end

  private

  def set_income
    @income = current_user.incomes.find(params[:id])
  end

  def income_params
    params.require(:income).permit(:amount, :description)
  end
end
