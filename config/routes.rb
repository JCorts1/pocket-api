Rails.application.routes.draw do
  devise_for :users, path: '', path_names: {
    sign_in: 'login',
    sign_out: 'logout',
    registration: 'signup'
  },
  controllers: {
    sessions: 'users/sessions',
    registrations: 'users/registrations'
  }

  namespace :api do
    namespace :v1 do
      resources :categories, only: [:index, :create, :show]
      resources :expenses, only: [:index, :create, :update, :destroy] do
        collection do
          get :export_csv
          post :scan_receipt
          post :create_from_receipt
        end
      end
      resources :incomes, only: [:index, :create, :update, :destroy]
      resources :budgets do
        collection do
          get :dashboard
        end
      end
    end
  end
end
