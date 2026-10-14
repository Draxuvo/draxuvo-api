module Api
  module V1
    # POST /api/v1/stripe/webhooks (research R11, contracts/api.md). Público: Stripe no manda
    # Authorization, así que la firma es la única prueba de origen y se exige siempre.
    class StripeWebhooksController < ApplicationController
      skip_before_action :authenticate_request

      def create
        event = construct_event
        Subscriptions::HandleWebhookService.new(event).call
        render json: { received: true }
      end

      private

      # El secreto se lee en cada request para que una rotación no requiera reiniciar.
      def construct_event
        secret = ENV["STRIPE_WEBHOOK_SECRET"]
        if secret.blank?
          Rails.logger.error("[stripe] STRIPE_WEBHOOK_SECRET no está configurado; webhook rechazado")
          raise ApiErrors::BadRequestError.new(details: I18n.t("errors.subscription.webhook_secret_missing"))
        end

        Stripe::Webhook.construct_event(request.body.read, request.headers["Stripe-Signature"].to_s, secret)
      rescue JSON::ParserError, Stripe::SignatureVerificationError
        raise ApiErrors::BadRequestError.new(details: I18n.t("errors.subscription.invalid_signature"))
      end
    end
  end
end
