Rails.application.routes.draw do
  root "dashboard#show"

  get "login", to: "sessions#new"
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy"
  resource :account, only: %i[edit update]

  resources :users, except: %i[show]

  resources :documents do
    collection do
      get :autocomplete
    end
    member do
      get :download
      post :reclassify
      post :assign
      post :create_issuer_category
    end
  end

  resources :categories

  # WebDAV — Finder, Cyberduck, scanners, curl (per-user Basic auth)
  # Rails' via: :all only includes standard HTTP verbs, so list WebDAV methods explicitly.
  webdav_methods = %i[get head put post delete options propfind proppatch mkcol copy move lock unlock]
  match "webdav", to: "webdav#handle", via: webdav_methods
  match "webdav/*path", to: "webdav#handle", via: webdav_methods, format: false

  get "up" => "rails/health#show", as: :rails_health_check
end
