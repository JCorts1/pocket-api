Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      get 'expenses/index'
      get 'expenses/create'
      get 'expenses/update'
      get 'expenses/destroy'
      get 'categories/index'
      get 'categories/create'
      get 'categories/show'
      # Routes for Categories
      resources :categories, only: [:index, :create, :show]

      # Routes for Expenses
      resources :expenses, only: [:index, :create, :update, :destroy]
    end
  end
end
