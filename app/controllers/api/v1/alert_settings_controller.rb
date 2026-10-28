module Api
  module V1
    # Tiempos límite, hora del resumen y zona horaria de las alertas de la empresa activa (spec 045, FR-016).
    # Solo dueño y administrador. Un PATCH cambia lo que trae y deja lo demás como estaba.
    class AlertSettingsController < BaseController
      before_action :require_boss!

      # GET /api/v1/alert_settings
      def show
        render json: payload(AlertSetting.for(current_company))
      end

      # PATCH /api/v1/alert_settings { thresholds: { table_open: 45 }, summary_hour: 9, time_zone: "America/Tijuana" }
      def update
        setting = AlertSetting.for(current_company)
        setting.merge_thresholds(params[:thresholds].to_unsafe_h) if params[:thresholds].respond_to?(:to_unsafe_h)
        setting.summary_hour = params[:summary_hour] if params.key?(:summary_hour)
        setting.time_zone = params[:time_zone] if params.key?(:time_zone)
        setting.save!
        render json: payload(setting)
      end

      private

      def payload(setting)
        {
          thresholds: setting.effective, defaults: AlertSetting::DEFAULTS,
          summary_hour: setting.summary_hour, time_zone: setting.time_zone,
          applicable: Alerts::Collector.applicable_kinds(current_company)
        }
      end
    end
  end
end
