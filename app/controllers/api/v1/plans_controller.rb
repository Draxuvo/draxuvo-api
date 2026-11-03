# Contrato: specs/002-rebrand-suscripciones/contracts/api.md (GET /plans).
# Público: el sitio web y la pantalla de registro lo consultan sin sesión.
module Api
  module V1
    class PlansController < ApplicationController
      skip_before_action :authenticate_request

      # GET /api/v1/plans
      def index
        render json: {
          iva_rate: Subscription::IVA_RATE,
          modules: Plan::PLAN_MODULES.map(&:to_s),
          plans: Plan.all.map { |plan| serialize_plan(plan) },
          addons: Addon.all.select(&:available?).map { |addon| serialize_addon(addon) }
        }
      end

      private

      def serialize_plan(plan)
        {
          key: plan.key.to_s,
          modules: plan.modules.map(&:to_s),
          prices: Plan::CYCLES.index_with { |cycle| price(plan.amount_cents(cycle)) }
        }
      end

      # Módulos extra contratables aparte del plan (spec 050).
      def serialize_addon(addon)
        {
          key: addon.key.to_s,
          requires: addon.requires.map(&:to_s),
          prices: Plan::CYCLES.index_with { |cycle| price(addon.amount_cents(cycle)) }
        }
      end

      def price(amount_cents)
        iva_cents = (amount_cents * Subscription::IVA_RATE).round
        { amount_cents: amount_cents, iva_cents: iva_cents, total_cents: amount_cents + iva_cents }
      end
    end
  end
end
