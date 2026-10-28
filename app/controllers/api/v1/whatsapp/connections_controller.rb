# Contrato: specs/047-configurar-whatsapp/contracts/api.md (/whatsapp/connection). Siempre `::Whatsapp::` dentro de
# `Api::V1`, para que el módulo de servicios no quede sombreado por este espacio de nombres.
module Api
  module V1
    module Whatsapp
      class ConnectionsController < BaseController
        include WhatsappAccess

        # PUT /api/v1/whatsapp/connection — verifica con Meta antes de guardar; si falla no se toca nada.
        def update
          connection = WhatsappConnection.current
          connection.lock_version = params[:lock_version] if params[:lock_version].present?
          token = params[:access_token].to_s.strip.presence
          secret = token || connection.token
          raise unprocessable("token_required", I18n.t("whatsapp_admin.errors.token_required")) if secret.blank?

          phone_number_id = params[:phone_number_id].presence || connection.phone_number_id
          waba_id = params[:waba_id].presence || connection.waba_id
          check = ::Whatsapp::ConnectionCheck.new(token: secret, phone_number_id: phone_number_id, waba_id: waba_id).call
          reject!(check) unless check.ok?

          replaced = token.present? && connection.token_present?
          save_connection(connection, token: token, phone_number_id: phone_number_id, waba_id: waba_id, check: check)
          WhatsappEvent.log!(action: replaced ? "token_replaced" : "connected", target: "connection", user: current_user,
                             data: { phone_number_id: phone_number_id, waba_id: waba_id })
          render_state
        end

        # POST /api/v1/whatsapp/connection/verify — «Verificar ahora» con la llave guardada.
        def verify
          connection = WhatsappConnection.current
          config = ::Whatsapp::Config.current
          raise unprocessable("not_connected", I18n.t("whatsapp_admin.errors.not_connected")) unless config.panel? && connection.token.present?

          check = ::Whatsapp::ConnectionCheck.new(token: connection.token, phone_number_id: connection.phone_number_id,
                                                  waba_id: connection.waba_id).call
          return render_unreachable if check.unreachable?

          check.ok? ? mark_verified(connection, check) : mark_failed(check)
          render_state
        end

        # DELETE /api/v1/whatsapp/connection — borra la llave y apaga el canal; conserva las plantillas elegidas.
        def destroy
          connection = WhatsappConnection.current
          connection.lock_version = params[:lock_version] if params[:lock_version].present?
          if connection.enabled? && !ActiveModel::Type::Boolean.new.cast(params[:confirm])
            raise unprocessable("confirmation_required", I18n.t("whatsapp_admin.errors.confirmation_required"))
          end

          connection.disconnect!
          WhatsappEvent.log!(action: "disconnected", target: "connection", user: current_user)
          render_state
        end

        private

        def save_connection(connection, token:, phone_number_id:, waba_id:, check:)
          attributes = { phone_number_id: phone_number_id, waba_id: waba_id, verified_name: check.verified_name,
                         display_phone_number: check.display_phone_number, status: "connected", error_code: nil,
                         error_message: nil, last_verified_at: Time.current, managed: true, problem_notified_at: nil }
          attributes[:access_token] = token if token
          connection.update!(attributes)
        end

        def mark_verified(connection, check)
          ::Whatsapp::Health.connection_recovered!
          connection.reload.update!(verified_name: check.verified_name, display_phone_number: check.display_phone_number,
                                    last_verified_at: Time.current)
          WhatsappEvent.log!(action: "verified", target: "connection", user: current_user)
        end

        def mark_failed(check)
          failure = ::Whatsapp::GraphClient::Failure.new(family: :connection, reason: check.reason, code: check.meta_code, message: check.message)
          ::Whatsapp::Health.record_failure(:verification_code, failure)
          WhatsappEvent.log!(action: "verified", target: "connection", user: current_user, result: "failed",
                             meta_code: check.meta_code, data: { reason: check.reason })
        end

        # Meta no respondió: el estado anterior queda intacto y se avisa con `stale: true`.
        def render_unreachable
          state = state_json
          state[:connection] = state[:connection].merge(stale: true)
          render json: state
        end

        def reject!(check)
          raise ApiErrors::ServiceUnavailableError.new(message: check.message, details: { code: "meta_unreachable" }) if check.unreachable?

          WhatsappEvent.log!(action: "connected", target: "connection", user: current_user, result: "failed",
                             meta_code: check.meta_code, data: { reason: check.reason })
          raise ApiErrors::UnprocessableEntityError.new(
            message: check.message, details: { code: "whatsapp_rejected", reason: check.reason, meta_code: check.meta_code&.to_s }
          )
        end

        def unprocessable(code, message)
          ApiErrors::UnprocessableEntityError.new(message: message, details: { code: code })
        end
      end
    end
  end
end
