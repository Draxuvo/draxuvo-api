module Api
  module V1
    # Tipos de aviso push que la persona recibe en la empresa activa (spec 057, FR-006 y FR-007). Abierto a todo miembro;
    # solo se ven y cambian los tipos que le corresponden por rol y por módulos activos (`available`). El correo de stock
    # bajo sigue en `/notification_preference`, que no cambia (FR-009).
    class PushPreferencesController < BaseController
      # GET /api/v1/push_preference
      def show
        render json: payload(NotificationPreference.for(current_user, current_company))
      end

      # PATCH /api/v1/push_preference { check_ready: false }
      def update
        preference = NotificationPreference.for(current_user, current_company)
        available.each do |kind|
          next unless params.key?(kind)

          preference.public_send("#{NotificationPreference::PUSH_KINDS.fetch(kind)}=", boolean!(params[kind]))
        end
        preference.save!
        render json: payload(preference)
      end

      private

      def available
        @available ||= ::Push::Kinds.available_for(current_role, current_company)
      end

      def payload(preference)
        { available: available }.merge(available.index_with { |kind| preference.push_enabled?(kind) })
      end

      def boolean!(value)
        return value if [ true, false ].include?(value)
        return value == "true" if %w[true false].include?(value)

        raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("push.errors.invalid_value"), details: { code: "invalid_value" })
      end
    end
  end
end
