class Api::V1::CategoriesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_category, only: [:show]

  # GET /api/v1/categories
  def index
    # Show default categories AND the user's own categories
    @default_categories = Category.where(is_default: true)
    @user_categories = current_user.categories
    @categories = (@default_categories + @user_categories).uniq.sort_by(&:name)
    render json: @categories
  end

  # GET /api/v1/categories/:id
  def show
    # set_category ensures we only find a category the user is allowed to see
    render json: @category.to_json(include: :expenses)
  end

  # POST /api/v1/categories
  def create
    @category = current_user.categories.build(category_params) # Associate with user
    # is_default will be false by default
    if @category.save
      render json: @category, status: :created
    else
      render json: @category.errors, status: :unprocessable_entity
    end
  end

  private

  def set_category
    # A user can see a default category or one they created themselves.
    # This prevents a user from seeing another user's custom categories.
    @category = Category.where(is_default: true).or(Category.where(user: current_user)).find(params[:id])
  end

  def category_params
    params.require(:category).permit(:name)
  end
end
