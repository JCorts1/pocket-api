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
      resources :expenses, only: [:index, :create, :update, :destroy]
      resources :incomes, only: [:index, :create, :update, :destroy]
    end
  end
end
