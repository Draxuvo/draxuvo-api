module Subscriptions
  # Resuelve el price id de Stripe por lookup_key `draxuvo_<plan>_<ciclo>` (research R9).
  # El resultado se guarda en cache 1 hora; un precio inexistente no se guarda.
  class PriceLookupService
    CACHE_TTL = 1.hour

    def self.price_id(plan_key, cycle)
      new(plan_key: plan_key, cycle: cycle).call
    end

    def initialize(plan_key:, cycle:)
      @plan_key = plan_key
      @cycle    = cycle
    end

    def call
      lookup_key = Plan.find(@plan_key).lookup_key(@cycle)
      price_id = Rails.cache.fetch(cache_key(lookup_key), expires_in: CACHE_TTL, skip_nil: true) do
        fetch_price_id(lookup_key)
      end
      price_id || raise(not_configured)
    rescue KeyError, ArgumentError
      raise ApiErrors::BadRequestError.new(details: I18n.t("errors.subscription.invalid_plan"))
    end

    private

    def fetch_price_id(lookup_key)
      prices = Stripe::Price.list(lookup_keys: [ lookup_key ], active: true)
      prices.data.find { |price| price.lookup_key == lookup_key }&.id
    end

    def cache_key(lookup_key)
      "stripe/price_id/#{lookup_key}"
    end

    # contracts/api.md (checkout): 400 con details stripe_not_configured cuando falta el precio.
    def not_configured
      ApiErrors::BadRequestError.new(details: I18n.t("errors.subscription.stripe_not_configured"))
    end
  end
end
