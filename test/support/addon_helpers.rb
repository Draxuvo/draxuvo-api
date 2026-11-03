# Ayudantes de las pruebas de módulos extra y punto de venta (spec 050).
module AddonHelpers
  # Deja contratado y vigente un módulo extra en la suscripción de la empresa, sin pasar por Stripe.
  def grant_addon!(company, key = :pos, ends_at: nil)
    subscription = company.billing_subscription
    addon = subscription.addons.find_or_initialize_by(module: key.to_s)
    addon.update!(company: subscription.company, stripe_item_id: "si_#{key}_#{company.id}", started_at: addon.started_at || 1.day.ago,
                  amount_cents: Addon.find(key).amount_cents(subscription.billing_cycle), ends_at: ends_at)
    company.reload
  end
end

ActiveSupport::TestCase.include AddonHelpers
