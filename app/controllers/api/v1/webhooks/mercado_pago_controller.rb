module Api
  module V1
    module Webhooks
      # POST /api/v1/webhooks/mercado_pago (spec 069, research R4, contracts/api.md). Público como el de Stripe: Mercado
      # Pago no manda JWT, así que la firma es la única prueba de origen y se exige siempre. El aviso solo dispara una
      # consulta: no se confía en su cuerpo. Responde en el acto (Mercado Pago espera 22 s y reintenta).
      class MercadoPagoController < ApplicationController
        skip_before_action :authenticate_request, raise: false

        def create
          notice = provider.parse_webhook(body: body_json, headers: signature_headers, params: request.query_parameters)
          handle(notice) if notice
          render json: { received: true }
        rescue TerminalProviders::InvalidSignature => e
          Rails.logger.warn("[webhooks:mercado_pago] firma rechazada: #{e.message}")
          render json: ApiErrors::BadRequestError.new(details: { code: "invalid_signature" }).as_json, status: :bad_request
        end

        private

        def provider = TerminalProviders.for("mercado_pago")

        def handle(notice)
          case notice.kind
          when :charge
            charge = TerminalCharge.find_by(provider_order_id: notice.external_id.to_s) ||
                     TerminalCharge.find_by("LOWER(provider_order_id) = ?", notice.external_id.to_s.downcase)
            if charge
              ::TerminalCharges::SyncJob.perform_later(charge.id)
            else
              TerminalEvent.log!(:webhook_ignored, external_id: notice.external_id.to_s.first(60))
            end
          when :disconnect
            TerminalConnection.where(provider: "mercado_pago", account_id: notice.account_id.to_s).where.not(status: "disconnected").find_each do |connection|
              connection.disconnect!
              TerminalEvent.log!(:disconnected, connection: connection, source: "provider")
              TerminalConnections::Health.new(connection).notify_owners("unauthorized")
            end
          end
        end

        def body_json
          JSON.parse(request.raw_post.presence || "{}")
        rescue JSON::ParserError
          {}
        end

        def signature_headers
          { "x-signature" => request.headers["x-signature"], "x-request-id" => request.headers["x-request-id"] }
        end
      end
    end
  end
end
