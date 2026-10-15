Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      # Auth
      post "auth/login", to: "authentication#login"
      get  "auth/me",    to: "authentication#me"

      # Passwords
      put  "passwords/update",            to: "passwords#update"
      post "passwords/reset",             to: "passwords#reset"
      put  "passwords/update_with_token", to: "passwords#update_with_token"

      # Profile
      get    "profile",        to: "profile#show"
      patch  "profile",        to: "profile#update"
      post   "profile/avatar", to: "profile#upload_avatar"
      delete "profile/avatar", to: "profile#remove_avatar"

      # Users
      resources :users do
        member do
          patch :update_active
          patch :active
        end
      end

      # Uploads
      resources :uploads, only: [ :index, :show, :create, :destroy ]

      # Company (usuario actual) + Companies (super_admin: CRUD global)
      resource  :company,   only: [ :show, :update ]
      resources :companies, only: [ :index, :show, :create, :update, :destroy ]

      # Módulos activos de la empresa actual: PATCH /api/v1/company/modules
      # Equipo (owner/admin) y sucursales (owner, plan Empresa) de la empresa actual
      resource :company, only: [] do
        patch :modules, to: "company_modules#update"
        patch :order_mode, to: "company_order_modes#update"
        resources :members, controller: "company_members", param: :user_id, only: [ :index, :create, :update, :destroy ]
        resources :branches, only: [ :index, :create ]
      end

      # Catálogo público de planes y alta pública de empresas
      resources :plans,         only: :index
      resources :registrations, only: :create

      # Suscripción de la empresa actual
      resource :subscription, only: [ :show, :update, :destroy ] do
        collection do
          post :checkout
          post :portal
        end
      end

      # Webhooks de Stripe (sin autenticación)
      post "stripe/webhooks", to: "stripe_webhooks#create"

      # Employees + checkin/checkout + sus asistencias
      resources :employees do
        member do
          post  :checkin
          post  :checkout
          patch :active
        end
      end

      # Asistencias (con filtros por employee, from, to)
      resources :attendances, only: [ :index ]

      # Inventario / Menú
      resources :products do
        collection do
          get  :menu
          post :import
          get  :template
        end
        resources :stock_movements, only: [ :index, :create ]
      end

      resources :units, only: [ :index ]

      resources :tickets, only: [ :index, :show ] do
        member do
          get   :download
          post  :send_whatsapp
        end
      end

      # WhatsApp OTP
      post "phone_verifications/send_code", to: "phone_verifications#send_code"
      post "phone_verifications/verify",    to: "phone_verifications#verify"

      get "dashboard", to: "dashboard#index"

      # Reports
      get "reports/summary",  to: "reports#summary"
      get "reports/income",   to: "reports#income"
      get "reports/expenses", to: "reports#expenses"
      get "reports/payroll",  to: "reports#payroll"

      resources :work_orders do
        collection do
          get :summary
        end
        member do
          %w[start finish reopen cancel charge void_charge].each do |action|
            post action, to: "work_orders#transition", defaults: { transition: action }
          end
          post   "items",                  to: "work_orders#create_item",  as: :create_item
          patch  "items/:item_id",         to: "work_orders#update_item",  as: :update_item
          delete "items/:item_id",         to: "work_orders#destroy_item", as: :destroy_item
          post   "steps",                  to: "work_orders#create_step",  as: :create_step
          patch  "steps/:step_id",         to: "work_orders#update_step",  as: :update_step
          delete "steps/:step_id",         to: "work_orders#destroy_step", as: :destroy_step
          post   "notes",                  to: "work_orders#create_note",  as: :create_note
          post   "photos",                 to: "work_orders#create_photo", as: :create_photo
          delete "photos/:photo_id",       to: "work_orders#destroy_photo", as: :destroy_photo
        end
      end
    end
  end
end
