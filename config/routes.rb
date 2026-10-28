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
      get "app_config", to: "app_config#show"
      resources :registrations, only: :create

      # Demo por plan (spec 039): abrirla es público; salir de ella y las aperturas necesitan sesión
      resources :demo_sessions, only: %i[create index] do
        delete :current, on: :collection, action: :finish
      end
      resources :demo_invites, only: %i[index create] do
        get :resolve, on: :collection
        post :revoke, on: :member
      end

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
      # Tipos de producto de la empresa (spec 016)
      resources :product_types, only: %i[index create update destroy] do
        post :move_products, on: :member
      end

      # Terminales de cobro del negocio (spec 015)
      resources :payment_terminals, only: %i[index create update destroy]

      resources :employees do
        member do
          post  :checkin
          post  :checkout
          patch :active
          get   :payroll_payments
          post   :access, action: :grant_access
          patch  :access, action: :update_access
          delete :access, action: :revoke_access
        end
      end

      # Nómina (spec 037): corridas, líneas de pago y ajustes
      resources :payroll_runs, only: %i[index show create destroy] do
        member do
          post :approve
          post :cancel
          post :pay_all
          post :refresh_employees
          get  :export
        end
      end
      resources :payroll_payments, only: %i[show update destroy] do
        post :pay, on: :member
        resources :adjustments, controller: "payroll_adjustments", only: :create
      end
      resources :payroll_adjustments, only: %i[update destroy]

      # Asistencias (con filtros por employee, from, to)
      resources :attendances, only: [ :index ] do
        get :roster, on: :collection
      end

      # Marca propia de entrada y salida (spec 026)
      scope :my_attendance, controller: :my_attendance, as: :my_attendance do
        get  :today
        post :check_in
        post :check_out
      end

      # Inventario / Menú
      resources :products do
        collection do
          get  :menu
          get  :by_code
          get  :export
          post :generate_barcodes
          post :import
          get  :template
        end
        resources :stock_movements, only: [ :index, :create ]
      end

      resources :product_imports, only: [ :index, :show ]
      post "barcodes/generate", to: "barcodes#generate"
      resources :label_formats, only: [ :index, :create, :update, :destroy ]
      post "labels/check", to: "labels#check"
      post "labels/pdf", to: "labels#pdf"
      resources :stock_receipts, only: [ :create ]
      resources :stock_counts, only: [ :index, :create, :show, :destroy ] do
        member do
          post :scan
          post :confirm
          patch "items/:product_id", action: :update_item
          delete "items/:product_id", action: :destroy_item
        end
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

      # Alertas operativas (spec 045)
      resource :alert_settings, only: %i[show update]
      resource :notification_preference, only: %i[show update]
      resources :alerts, only: :index do
        collection do
          post   :snooze, to: "alert_snoozes#create"
          delete :snooze, to: "alert_snoozes#destroy"
        end
      end

      # Restaurante (spec 013): mesas, cuentas, comandas, estaciones y cobro
      namespace :restaurant do
        resources :stations, only: %i[index create update] do
          get  "board",                  to: "station_boards#show"
          post "items/:id/advance",      to: "station_items#advance"
          post "kitchen_orders/:id/advance", to: "station_orders#advance"
        end
        resources :tables, only: :index
        resources :tables, only: %i[create update], controller: "dining_tables"
        resources :stock_alerts, only: :index
        resources :checks, only: %i[create show update] do
          get :waiters, on: :collection
          member do
            post :cancel
            post :rounds,   to: "rounds#create"
            post :payments, to: "payments#create"
            post :close,    to: "check_closures#create"
          end
          resources :items, only: %i[create update destroy], controller: "check_items" do
            member do
              post :deliver, to: "deliveries#create"
              post :cancel,  to: "item_cancellations#create"
            end
          end
        end
      end

      # Reports
      get "reports/summary",  to: "reports#summary"
      get "reports/income",   to: "reports#income"
      get "reports/expenses", to: "reports#expenses"
      get "reports/payroll",  to: "reports#payroll"
      get "reports/inventory", to: "reports#inventory"

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
