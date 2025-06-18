class Api::V1::CategoriesController < ApplicationController
  # GET /api/v1/categories
  def index
    @categories = Category.all.order(:name)
    render json: @categories
  end

  # GET /api/v1/categories/:id
  def show
    @category = Category.find(params[:id])
    # We can include the expenses for that category
    render json: @category.to_json(include: :expenses)
  end

  # POST /api/v1/categories
  def create
    @category = Category.new(category_params)
    # is_default will be false by default
    if @category.save
      render json: @category, status: :created
    else
      render json: @category.errors, status: :unprocessable_entity
    end
  end

  private

  def category_params
    params.require(:category).permit(:name)
  end
end
