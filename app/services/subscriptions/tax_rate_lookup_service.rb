module Subscriptions
  # Resuelve la tasa de IVA (16 %, no incluida en el precio) de Stripe por su metadata `draxuvo_tax=iva_16`.
  # Se aplica a cada suscripción nueva para que Stripe cobre el IVA además del precio (spec 042).
  # El resultado se guarda en cache 1 hora; una tasa inexistente no se guarda.
  class TaxRateLookupService
    CACHE_TTL = 1.hour
    METADATA_KEY = "draxuvo_tax".freeze
    METADATA_VALUE = "iva_16".freeze
    CACHE_KEY = "stripe/tax_rate_id/#{METADATA_VALUE}".freeze

    def self.tax_rate_id
      new.call
    end

    def call
      tax_rate_id = Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL, skip_nil: true) { fetch_tax_rate_id }
      tax_rate_id || raise(not_configured)
    end

    private

    def fetch_tax_rate_id
      Stripe::TaxRate.list(active: true, limit: 100).data.find { |rate| iva?(rate) }&.id
    end

    def iva?(rate)
      rate.metadata&.[](METADATA_KEY) == METADATA_VALUE && rate.percentage.to_f == 16.0 && !rate.inclusive
    end

    # Igual que un precio faltante: el checkout falla cerrado en lugar de cobrar sin IVA.
    def not_configured
      ApiErrors::BadRequestError.new(details: I18n.t("errors.subscription.stripe_not_configured"))
    end
  end
end
