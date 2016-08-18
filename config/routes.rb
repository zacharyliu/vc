Rails.application.routes.draw do
  root 'welcome#index'

  devise_for :users, :controllers => { :omniauth_callbacks => "users/omniauth_callbacks" }

  resources :knowledges, only: [:index]
  get 'all', to: 'companies#all'
  get 'voting', to: 'companies#voting'
  resources :companies, only: [:index, :show] do
    resources :votes, only: [:show, :create, :new]
  end
  namespace :api, constraints: { format: :json } do
    namespace :v1 do
      resources :companies, only: [:index, :show] do
        member do
          post 'allocate'
          post 'reject'
        end
        collection do
          get 'search'
        end
      end
      resource :user, only: :show do
        get 'token'
        post 'toggle_active'
      end
    end
  end
end
