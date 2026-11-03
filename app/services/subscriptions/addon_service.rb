module Subscriptions
  # Contrata, da de baja y reactiva un módulo extra de la suscripción (spec 050, research R3 y R4).
  # - add: un segundo renglón en la suscripción de Stripe, con el ciclo del plan y cobro proporcional inmediato. Si el
  #   cobro falla, Stripe rechaza el alta y no queda ni renglón ni fila: el módulo no se activa.
  # - remove: quita el renglón sin prorrateo ni reembolso y deja el acceso hasta el fin del periodo ya pagado.
  # - reactivate: vuelve a agregar el renglón sin cobrar de nuevo (el periodo ya está pagado).
  class AddonService
    def initialize(company:, actor: nil)
      @company = company
      @actor = actor
      @subscription = company.billing_subscription
    end

    def add(key)
      Demo::Guard.restrict!(:payment)
      addon = find_addon!(key)
      ensure_paid_subscription!
      ensure_requirements!(addon)
      row = @subscription.addons.find_by(module: addon.key.to_s)
      fail!(:already_active, :addon_already_active) if row&.current? && row.ends_at.nil?
      fail!(:already_ending, :addon_already_ending) if row&.ending?

      item = create_item(addon, proration: "always_invoice", payment_behavior: "error_if_incomplete")
      row ||= @subscription.addons.new(module: addon.key.to_s)
      row.update!(company: @subscription.company, stripe_item_id: item.id, amount_cents: addon.amount_cents(@subscription.billing_cycle),
                  started_at: Time.current, ends_at: nil)
      @subscription.log_change!("addon_added", actor: @actor, reason: addon.key.to_s)
      row
    end

    def remove(key)
      Demo::Guard.restrict!(:plan_change)
      addon = find_addon!(key)
      row = @subscription&.addons&.find_by(module: addon.key.to_s)
      fail!(:not_found, :addon_not_found, status: :not_found) unless row&.current?
      fail!(:already_ending, :addon_already_ending) if row.ending?

      Stripe::SubscriptionItem.delete(row.stripe_item_id, { proration_behavior: "none" }) if row.stripe_item_id.present?
      row.update!(ends_at: @subscription.current_period_end || Time.current, stripe_item_id: nil)
      @subscription.log_change!("addon_removed", actor: @actor, reason: addon.key.to_s)
      row
    end

    def reactivate(key)
      Demo::Guard.restrict!(:plan_change)
      addon = find_addon!(key)
      row = @subscription&.addons&.find_by(module: addon.key.to_s)
      fail!(:not_found, :addon_not_found, status: :not_found) unless row
      fail!(:not_ending, :addon_not_ending) unless row.ending?

      item = create_item(addon, proration: "none", payment_behavior: nil)
      row.update!(stripe_item_id: item.id, ends_at: nil)
      @subscription.log_change!("addon_reactivated", actor: @actor, reason: addon.key.to_s)
      row
    end

    private

    def find_addon!(key)
      raise ApiErrors::NotFoundError unless @subscription

      Addon.find(key.to_s)
    rescue KeyError
      fail!(:unknown, :unknown_addon)
    end

    # Solo una suscripción pagada y vigente puede sumar un extra; en prueba se contrata con el checkout.
    def ensure_paid_subscription!
      fail!(:not_paid, :subscription_suspended, message: I18n.t("errors.subscription.suspended")) if @subscription.suspended?
      return if (@subscription.active? || @subscription.past_due?) && @subscription.stripe_subscription_id.present?

      fail!(:not_paid, :subscription_not_paid)
    end

    def ensure_requirements!(addon)
      missing = addon.requires.reject { |module_key| @company.module_active?(module_key) }
      return if missing.empty?

      fail!(:requires_module, :addon_requires_module, module: I18n.t("modules.#{missing.first}"), required: missing.first.to_s)
    end

    def create_item(addon, proration:, payment_behavior:)
      params = {
        subscription: @subscription.stripe_subscription_id,
        price: PriceLookupService.addon_price_id(addon.key, @subscription.billing_cycle),
        quantity: 1,
        proration_behavior: proration
      }
      params[:payment_behavior] = payment_behavior if payment_behavior
      Stripe::SubscriptionItem.create(params)
    rescue Stripe::CardError => e
      Rails.logger.warn("[Subscriptions::AddonService] cobro rechazado addon=#{addon.key}: #{e.message}")
      fail!(:payment_failed, :addon_payment_failed, status: :payment_required)
    rescue Stripe::StripeError => e
      Rails.logger.error("[Subscriptions::AddonService] Stripe falló addon=#{addon.key}: #{e.class} #{e.message}")
      raise ApiErrors::ServiceUnavailableError.new(message: I18n.t("addon.errors.payment_failed"), details: { code: "stripe_unavailable" })
    end

    def fail!(i18n_key, code, status: :unprocessable_entity, message: nil, **details)
      raise ApiErrors::BaseError.new(
        status: status, message: message || I18n.t("addon.errors.#{i18n_key}", **details.slice(:module)), details: { code: code.to_s, **details.except(:module) }
      )
    end
  end
end
