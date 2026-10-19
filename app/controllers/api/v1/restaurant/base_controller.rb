module Api
  module V1
    module Restaurant
      # Base del módulo: hereda la autenticación, el scope por empresa y la gate de suscripción de BaseController.
      class BaseController < Api::V1::BaseController
        include Idempotent

        requires_module :restaurant

        private

        def restaurant_context
          @restaurant_context ||= ::Restaurant::Permissions::Context.new(user: current_user, role: current_role)
        end

        def checks_scope = current_company.checks

        def serialize_check(check)
          CheckSerializer.new(check, context: restaurant_context).as_json
        end

        def find_check(id = params[:id])
          checks_scope.includes(:dining_table, :waiter).find(id)
        end

        def invalid!(code, **opts)
          raise ApiErrors::UnprocessableEntityError.new(
            message: I18n.t("restaurant.errors.#{code}", **opts), details: { code: code.to_s }
          )
        end
      end
    end
  end
end
