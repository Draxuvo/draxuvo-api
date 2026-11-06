# «Cobro solo por jefes» de la empresa (spec 058, contracts/api.md). Solo el super admin lo lee y lo cambia, con
# `X-Company-Id` de la empresa que administra, igual que los módulos (spec 017).
module Api
  module V1
    class CompanyChargePoliciesController < BaseController
      before_action :require_super_admin!

      # GET /api/v1/company/charge_policy
      def show
        render json: policy_json
      end

      # PATCH /api/v1/company/charge_policy { boss_only_charge: true|false }
      def update
        raise ApiErrors::BadRequestError.new(details: "boss_only_charge") unless params.key?(:boss_only_charge)

        ChargePolicy::Update.call(current_company, current_user, ActiveModel::Type::Boolean.new.cast(params[:boss_only_charge]) == true)
        render json: policy_json
      end

      private

      def policy_json
        changes = current_company.charge_policy_changes.includes(:actor).order(created_at: :desc, id: :desc).limit(10)
        {
          boss_only_charge: current_company.reload.boss_only_charge,
          changes: changes.map { |change| { enabled: change.enabled, actor: change.actor.full_name, created_at: change.created_at } }
        }
      end
    end
  end
end
