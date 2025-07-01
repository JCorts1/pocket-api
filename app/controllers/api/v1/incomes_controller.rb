class Api::V1::IncomesController < ApplicationController

  before_action :authenticate_user!
  before_action :set_income, only: [:update, :destroy]


  def index

    @incomes = current_user.incomes.order(created_at: :desc)
    render json: @incomes
  end


  def create

    @income = current_user.incomes.build(income_params)

    if @income.save
      render json: @income, status: :created
    else
      render json: { error: @income.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  def update
    if @income.update(income_params)
      render json: @income
    else
      render json: { error: @income.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

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
