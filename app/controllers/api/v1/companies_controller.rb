# app/controllers/api/v1/companies_controller.rb
module Api
  module V1
    class CompaniesController < BaseController
      before_action :require_super_admin!, only: [ :index, :create, :destroy ]
      before_action :set_company, only: [ :show, :update, :destroy ]

      # GET /api/v1/companies — super_admin: lista todas las empresas
      def index
        # Spec 039: las demos (una por visita) no se mezclan con los clientes reales.
        companies = Company.real.includes(:users).order(created_at: :desc)
        @pagy, companies = pagy(companies)
        serialized = ActiveModelSerializers::SerializableResource.new(companies).as_json
        render json: paginate_response(@pagy, serialized)
      end

      # GET /api/v1/company  (singular, usuario actual)
      # GET /api/v1/companies/:id  (super_admin por id)
      def show
        render json: @company
      end

      # POST /api/v1/companies — super_admin: crea empresa (after_create abre la prueba Pro)
      def create
        # save! deja subir el RecordInvalid de los after_create (suscripción, tipos de producto): `save` lo
        # traga y devolvía 422 con details vacío (spec 044).
        company = Company.new(company_params)
        company.save!
        render json: company, status: :created
      end

      # PATCH /api/v1/company  (usuario actual)
      # PATCH /api/v1/companies/:id  (super_admin por id)
      def update
        @company.update!(company_params)
        render json: @company
      end

      # DELETE /api/v1/companies/:id — super_admin
      # Con suscripción en Stripe, la cancela allá de inmediato antes de borrar (FR-022).
      def destroy
        subscription = @company.subscription
        if subscription&.stripe_subscription_id.present?
          Subscriptions::CancelService.new(subscription, immediate: true).call
        end
        @company.destroy
        head :no_content
      end

      private

      def set_company
        if params[:id].present?
          require_super_admin!
          @company = Company.find(params[:id])
        else
          @company = current_company
        end
      rescue ActiveRecord::RecordNotFound
        raise ApiErrors::NotFoundError.new(message: I18n.t("companies.not_found"))
      end

      def company_params
        params.require(:company).permit(:name)
      end
    end
  end
end
