# Spec 055 (H-61): una ruta o un verbo que no existe bajo /api/v1 responde el JSON de error común y no la página HTML de
# Rails. No exige sesión: no revela nada y un cliente sin token recibe lo mismo que uno con token.
module Api
  module V1
    class NotFoundController < ActionController::API
      def show
        error = ApiErrors::NotFoundError.new(message: I18n.with_locale(locale) { I18n.t("errors.route_not_found") })
        render json: error.as_json, status: :not_found
      end

      private

      def locale
        wanted = request.headers["Accept-Language"].to_s[/\A[a-z]{2}/]&.to_sym
        I18n.available_locales.include?(wanted) ? wanted : I18n.default_locale
      end
    end
  end
end
