module Api
  module V1
    # Posponer una alerta de tiempo por un plazo fijo (spec 045). Vale para todos los jefes de la empresa.
    class AlertSnoozesController < BaseController
      before_action :require_boss!

      # POST /api/v1/alerts/snooze { kind, subject_key, minutes }
      def create
        kind = params[:kind].to_s
        unless AlertSnooze::KINDS.include?(kind)
          raise ApiErrors::UnprocessableEntityError.new(details: [ I18n.t("alerts.errors.not_snoozable") ])
        end

        minutes = params[:minutes].to_i
        unless AlertSnooze::MINUTES.include?(minutes)
          raise ApiErrors::UnprocessableEntityError.new(details: [ I18n.t("alerts.errors.invalid_minutes") ])
        end

        snooze = current_company.alert_snoozes.find_or_initialize_by(kind: kind, subject_key: params.require(:subject_key).to_s)
        snooze.update!(snoozed_until: minutes.minutes.from_now, user: current_user)
        render json: { id: "#{kind}:#{snooze.subject_key}", snoozed_until: snooze.snoozed_until, snoozed_by: current_user.full_name },
               status: :created
      end

      # DELETE /api/v1/alerts/snooze?kind=...&subject_key=...
      def destroy
        current_company.alert_snoozes.where(kind: params[:kind].to_s, subject_key: params[:subject_key].to_s).delete_all
        head :no_content
      end
    end
  end
end
