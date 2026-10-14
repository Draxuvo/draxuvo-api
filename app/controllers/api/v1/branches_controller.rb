# Contrato: specs/004-refactor-web-panel/contracts/api.md ("/company/branches"). R17, FR-027, FR-028.
# Sucursales del plan Empresa: un solo nivel, hasta 3 empresas por cuenta (principal incluida).
# Usan la suscripción y los módulos de la principal; no se les crea prueba propia.
module Api
  module V1
    class BranchesController < BaseController
      before_action :require_owner!

      # GET /api/v1/company/branches — la principal y sus sucursales, también desde una sucursal.
      def index
        main = current_company.billing_company || current_company
        render json: [ main, *main.branches.order(:id) ].map { |company| company_json(company) }
      end

      # POST /api/v1/company/branches { branch: { name } }
      def create
        main = current_company
        unprocessable!("not_a_main_company") if main.branch?
        raise_module_not_in_plan!(:multi_company) unless main.module_active?(:multi_company)
        unprocessable!("company_limit_reached") if 1 + main.branches.count >= Company::MAX_COMPANIES_PER_ACCOUNT

        branch = ActiveRecord::Base.transaction do
          created = Company.create!(name: branch_params[:name], slug: available_slug(branch_params[:name]), parent: main)
          created.user_companies.create!(user: current_user, role: :owner) unless current_user.super_admin?
          created
        end

        render json: { company: company_json(branch), user: UserSerializer.new(current_user.reload).as_json },
               status: :created
      end

      private

      def branch_params
        params.require(:branch).permit(:name)
      rescue ActionController::ParameterMissing => e
        raise ApiErrors::BadRequestError.new(message: e.message)
      end

      def company_json(company)
        { id: company.id, name: company.name, slug: company.slug, parent_company_id: company.parent_company_id }
      end

      def unprocessable!(code)
        raise ApiErrors::UnprocessableEntityError.new(
          message: I18n.t("branches.#{code}"),
          details: { code: code, limit: (Company::MAX_COMPANIES_PER_ACCOUNT if code == "company_limit_reached") }.compact
        )
      end

      # Como en el registro: si el slug existe se le agrega un sufijo numérico.
      def available_slug(name)
        base = name.to_s.parameterize
        return nil if base.blank?

        slug = base
        suffix = 1
        slug = "#{base}-#{suffix += 1}" while Company.exists?(slug: slug)
        slug
      end
    end
  end
end
