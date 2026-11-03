# Ayudantes de Stripe compartidos por los tests de suscripciones y webhooks.
module StripeHelpers
  ALL_LOOKUP_KEYS = (%w[basic pro enterprise].product(%w[monthly annual]).map { |p, c| "draxuvo_#{p}_#{c}" } +
                     %w[monthly annual].map { |c| "draxuvo_addon_pos_#{c}" }).freeze

  # Suscripción de Stripe como la devuelve la API (versión acacia), con el periodo también en el item.
  def stripe_sub_hash(id:, status:, lookup_key:, cancel_at_period_end: false, customer: "cus_test",
                      period_start: 1.day.ago, period_end: 29.days.from_now, metadata: {}, extra_lookup_keys: [])
    extra_items = extra_lookup_keys.map do |key|
      { id: "si_#{key}", object: "subscription_item", current_period_start: period_start.to_i, current_period_end: period_end.to_i,
        price: { id: "price_#{key}", object: "price", lookup_key: key } }
    end
    {
      id: id,
      object: "subscription",
      customer: customer,
      status: status,
      cancel_at_period_end: cancel_at_period_end,
      canceled_at: (status == "canceled" ? Time.now.to_i : nil),
      current_period_start: period_start.to_i,
      current_period_end: period_end.to_i,
      metadata: metadata,
      items: {
        object: "list",
        data: [
          {
            id: "si_#{id}",
            object: "subscription_item",
            current_period_start: period_start.to_i,
            current_period_end: period_end.to_i,
            price: { id: "price_#{lookup_key}", object: "price", lookup_key: lookup_key }
          },
          *extra_items
        ]
      }
    }
  end

  # Simula Stripe::Price.list (por lookup_keys), Stripe::TaxRate.list, Stripe::Customer.create y
  # Stripe::Checkout::Session.create. Devuelve los parámetros con que se creó la sesión.
  # `tax_rates: false` deja la cuenta sin la tasa de IVA.
  def with_checkout_stubs(prices: ALL_LOOKUP_KEYS, tax_rates: true)
    captured = nil

    price_list = lambda do |params = {}, *_rest|
      requested = Array(params.to_h.with_indifferent_access[:lookup_keys]).map(&:to_s)
      keys = requested.empty? ? prices : prices & requested
      Stripe::ListObject.construct_from(
        object: "list",
        data: keys.map { |key| { id: "price_#{key}", object: "price", lookup_key: key, active: true } }
      )
    end
    tax_rate_list = lambda do |*|
      Stripe::ListObject.construct_from(
        object: "list",
        data: tax_rates ? [ { id: "txr_iva_16", object: "tax_rate", percentage: 16.0, inclusive: false, active: true,
                              metadata: { draxuvo_tax: "iva_16" } } ] : []
      )
    end
    customer_create = ->(*) { Stripe::StripeObject.construct_from(id: "cus_new", object: "customer") }
    session_create = lambda do |params = {}, *_rest|
      captured = params.to_h.deep_symbolize_keys
      Stripe::StripeObject.construct_from(id: "cs_test_123", object: "checkout.session",
                                          url: "https://checkout.stripe.com/c/pay/cs_test_123")
    end

    Stripe::Price.stub(:list, price_list) do
      Stripe::TaxRate.stub(:list, tax_rate_list) do
        Stripe::Customer.stub(:create, customer_create) do
          Stripe::Checkout::Session.stub(:create, session_create) do
            yield
          end
        end
      end
    end

    captured
  end

  # Simula la cancelación programada en Stripe. `calls` recibe cada Stripe::Subscription.update.
  def with_cancel_stubs(calls, stripe_id: "sub_pro", lookup_key: "draxuvo_pro_monthly")
    period_start = 5.days.ago.to_i
    period_end = 25.days.from_now.to_i
    stripe_sub = Stripe::Subscription.construct_from(
      id: stripe_id,
      object: "subscription",
      status: "active",
      cancel_at_period_end: true,
      current_period_start: period_start,
      current_period_end: period_end,
      items: {
        object: "list",
        data: [ {
          id: "si_123",
          object: "subscription_item",
          current_period_start: period_start,
          current_period_end: period_end,
          price: { id: "price_#{lookup_key}", object: "price", lookup_key: lookup_key }
        } ]
      }
    )

    update = lambda do |id, params = {}, *_rest|
      calls << { id: id, params: params.to_h.deep_symbolize_keys }
      stripe_sub
    end

    Stripe::Subscription.stub(:update, update) do
      Stripe::Subscription.stub(:retrieve, ->(*) { stripe_sub }) do
        Stripe::Subscription.stub(:cancel, ->(*) { flunk "Stripe should not cancel immediately" }) do
          yield
        end
      end
    end
  end
end

# Simula el alta y la baja de un renglón de módulo extra (spec 050). `created` y `deleted` reciben cada llamada.
# `charge_error: true` hace que Stripe rechace el cobro proporcional; `outage: true`, que no responda.
module AddonStripeHelpers
  def with_addon_stubs(created: [], deleted: [], charge_error: false, outage: false, prices: StripeHelpers::ALL_LOOKUP_KEYS)
    price_list = lambda do |params = {}, *_rest|
      requested = Array(params.to_h.with_indifferent_access[:lookup_keys]).map(&:to_s)
      Stripe::ListObject.construct_from(
        object: "list", data: (prices & requested).map { |key| { id: "price_#{key}", object: "price", lookup_key: key, active: true } }
      )
    end
    create = lambda do |params = {}, *_rest|
      created << params.to_h.deep_symbolize_keys
      raise Stripe::APIConnectionError, "sin red" if outage
      raise Stripe::CardError.new("Your card was declined.", "card_declined", http_status: 402) if charge_error

      Stripe::StripeObject.construct_from(id: "si_new_#{created.size}", object: "subscription_item")
    end
    delete = lambda do |id, params = {}, *_rest|
      deleted << { id: id, params: params.to_h.deep_symbolize_keys }
      Stripe::StripeObject.construct_from(id: id, deleted: true)
    end
    Stripe::Price.stub(:list, price_list) do
      Stripe::SubscriptionItem.stub(:create, create) do
        Stripe::SubscriptionItem.stub(:delete, delete) { yield }
      end
    end
  end
end

ActiveSupport::TestCase.include AddonStripeHelpers
