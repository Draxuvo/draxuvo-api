require "test_helper"

class Subscriptions::AddonServiceTest < ActiveSupport::TestCase
  setup do
    @company = companies(:basic_co)
    @subscription = subscriptions(:basic_co)
    @owner = users(:basic_co_owner)
    @created = []
    @deleted = []
  end

  def service(company = @company) = Subscriptions::AddonService.new(company: company, actor: @owner)

  def stubs(**options, &block) = with_memory_cache { with_addon_stubs(created: @created, deleted: @deleted, **options, &block) }

  def error_of(&block) = assert_raises(ApiErrors::BaseError, &block)

  # --- contratar ---

  test "adds a second item with the plan cycle and an immediate prorated charge" do
    row = stubs { service.add("pos") }

    assert_equal 1, @created.size
    assert_equal({ subscription: "sub_basic", price: "price_draxuvo_addon_pos_monthly", quantity: 1,
                   proration_behavior: "always_invoice", payment_behavior: "error_if_incomplete" }, @created.first)
    assert row.persisted?
    assert_equal "pos", row.module
    assert_equal "si_new_1", row.stripe_item_id
    assert_equal 19_900, row.amount_cents
    assert_nil row.ends_at
    assert @company.reload.module_active?(:pos)
    assert_equal 19_900, @subscription.reload.addons_cents
  end

  test "an annual subscription gets the annual price" do
    @subscription.update!(billing_cycle: :annual)
    row = stubs { service.add(:pos) }

    assert_equal "price_draxuvo_addon_pos_annual", @created.first[:price]
    assert_equal 199_000, row.amount_cents
  end

  test "records who added it" do
    stubs { service.add("pos") }
    change = @subscription.subscription_changes.order(:id).last
    assert_equal "addon_added", change.kind
    assert_equal "pos", change.reason
    assert_equal @owner, change.actor
  end

  test "a declined prorated charge leaves nothing behind" do
    error = error_of { stubs(charge_error: true) { service.add("pos") } }

    assert_equal :payment_required, error.status
    assert_equal "addon_payment_failed", error.details[:code]
    assert_empty @subscription.addons.reload
    assert_not @company.reload.module_active?(:pos)
    assert_empty @subscription.subscription_changes
  end

  test "an unknown module is rejected" do
    assert_equal "unknown_addon", error_of { stubs { service.add("inventory") } }.details[:code]
    assert_empty @created
  end

  test "needs the modules it depends on" do
    @company.update!(disabled_modules: [ "inventory" ])
    error = error_of { stubs { service.add("pos") } }

    assert_equal "addon_requires_module", error.details[:code]
    assert_match(/Inventario/, error.message)
    assert_empty @created
  end

  test "cannot be added twice" do
    stubs { service.add("pos") }
    assert_equal "addon_already_active", error_of { stubs { service.add("pos") } }.details[:code]
    assert_equal 1, @created.size
  end

  test "in the trial it is added without a charge or a Stripe item (spec 053)" do
    company = companies(:one)
    row = stubs { service(company).add("pos") }

    assert_empty @created
    assert_nil row.stripe_item_id
    assert_equal 19_900, row.amount_cents
    assert company.reload.module_active?(:pos)
  end

  test "in the trial turning it off is immediate and deletes nothing in Stripe" do
    company = companies(:one)
    stubs { service(company).add("pos") }
    stubs { service(company).remove("pos") }

    assert_nil company.billing_subscription.addons.find_by(module: "pos")
    assert_not company.reload.module_active?(:pos)
    assert_empty @deleted
  end

  test "it is not added while its prices are missing" do
    error = with_env("ADDON_POS_ENABLED" => "false") { error_of { stubs { service.add("pos") } } }
    assert_equal "addon_not_available", error.details[:code]
    assert_empty @created
  end

  test "records the history with the price before and after" do
    stubs { service.add("pos") }
    stubs { service.remove("pos") }
    changes = @company.module_changes.where(module: "pos").order(:id).pluck(:enabled, :amount_before_cents, :amount_after_cents)
    assert_equal [ [ true, 0, 19_900 ], [ false, 19_900, 0 ] ], changes
  end

  test "an expired or suspended subscription cannot add it" do
    assert_equal "subscription_not_paid", error_of { stubs { service(companies(:expired_co)).add("pos") } }.details[:code]
    @subscription.update_columns(status: Subscription.statuses[:suspended], suspended_at: Time.current)
    assert_equal "subscription_suspended", error_of { stubs { service.add("pos") } }.details[:code]
  end

  test "a past due subscription can still add it" do
    @subscription.update_columns(status: Subscription.statuses[:past_due])
    assert_nothing_raised { stubs { service.add("pos") } }
  end

  test "a demo cannot pay" do
    Demo::Guard.stub(:active?, true) do
      assert_raises(Demo::Restricted) { stubs { service.add("pos") } }
    end
  end

  test "a stripe outage is a service unavailable, not a payment error" do
    error = error_of { stubs(outage: true) { service.add("pos") } }

    assert_equal :service_unavailable, error.status
    assert_empty @subscription.addons.reload
  end

  # --- baja ---

  test "removing keeps access until the end of the paid period and stops charging" do
    grant_addon!(@company, :pos)
    @subscription.addons.first.update!(stripe_item_id: "si_pos_1")
    row = stubs { service.remove("pos") }

    assert_equal [ { id: "si_pos_1", params: { proration_behavior: "none" } } ], @deleted
    assert_in_delta @subscription.current_period_end.to_f, row.ends_at.to_f, 1
    assert_nil row.stripe_item_id
    assert row.ending?
    assert @company.reload.module_active?(:pos)
    assert_equal "addon_removed", @subscription.subscription_changes.order(:id).last.kind
  end

  test "removing twice or something not subscribed fails" do
    error = error_of { stubs { service.remove("pos") } }
    assert_equal :not_found, error.status
    assert_equal "addon_not_found", error.details[:code]

    grant_addon!(@company, :pos)
    stubs { service.remove("pos") }
    assert_equal "addon_already_ending", error_of { stubs { service.remove("pos") } }.details[:code]
  end

  test "after the period ends the module is gone" do
    grant_addon!(@company, :pos)
    stubs { service.remove("pos") }
    @subscription.addons.update_all(ends_at: 1.minute.ago)

    assert_not @company.reload.module_active?(:pos)
    assert_equal 0, @subscription.reload.addons_cents
  end

  # --- reactivar ---

  test "reactivating before the end adds the item back without a new charge" do
    grant_addon!(@company, :pos)
    stubs { service.remove("pos") }
    row = stubs { service.reactivate("pos") }

    assert_equal "none", @created.last[:proration_behavior]
    assert_not @created.last.key?(:payment_behavior)
    assert_nil row.ends_at
    assert_equal "addon_reactivated", @subscription.subscription_changes.order(:id).last.kind
  end

  test "only an ending add-on can be reactivated" do
    grant_addon!(@company, :pos)
    assert_equal "addon_not_ending", error_of { stubs { service.reactivate("pos") } }.details[:code]
    assert_equal :not_found, error_of { stubs { service(companies(:pro_co)).reactivate("pos") } }.status
  end

  test "an add-on that already ended can be contracted again with a charge" do
    grant_addon!(@company, :pos, ends_at: 2.days.ago)
    assert_not @company.reload.module_active?(:pos)

    row = stubs { service.add("pos") }
    assert_equal "always_invoice", @created.last[:proration_behavior]
    assert_nil row.ends_at
    assert @company.reload.module_active?(:pos)
    assert_equal 1, @subscription.addons.count
  end

  test "a branch has no subscription of its own to change" do
    branch = Company.create!(name: "Sucursal", parent: companies(:pro_co))
    assert_equal subscriptions(:pro_co), branch.billing_subscription
  end
end
