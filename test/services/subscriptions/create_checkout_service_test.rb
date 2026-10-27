require "test_helper"

class Subscriptions::CreateCheckoutServiceTest < ActiveSupport::TestCase
  def service(company, **opts)
    Subscriptions::CreateCheckoutService.new(
      company: company, plan: :pro, success_url: "https://app.test/ok", cancel_url: "https://app.test/no", **opts
    )
  end

  test "creates a checkout session with the plan price and metadata" do
    company = companies(:one)
    result = nil
    captured = with_memory_cache do
      with_checkout_stubs { result = service(company, billing_cycle: "annual").call }
    end
    assert_equal({ checkout_url: "https://checkout.stripe.com/c/pay/cs_test_123" }, result)
    assert_equal "cus_new", captured[:customer]
    assert_equal company.id.to_s, captured[:client_reference_id]
    assert_equal "subscription", captured[:mode]
    assert_equal [ { price: "price_draxuvo_pro_annual", quantity: 1 } ], captured[:line_items]
    assert_equal({ company_id: company.id, plan: "pro", billing_cycle: "annual" }, captured[:metadata])
    assert_equal "https://app.test/ok", captured[:success_url]
  end

  test "billing cycle defaults to monthly" do
    captured = with_memory_cache { with_checkout_stubs { service(companies(:one), billing_cycle: "").call } }
    assert_equal "monthly", captured[:metadata][:billing_cycle]
    assert_equal "price_draxuvo_pro_monthly", captured[:line_items].first[:price]
  end

  test "creates and stores the Stripe customer when the company has none" do
    company = companies(:one)
    with_memory_cache { with_checkout_stubs { service(company).call } }
    assert_equal "cus_new", company.reload.stripe_id
  end

  test "reuses the existing Stripe customer" do
    company = companies(:one)
    company.update_column(:stripe_id, "cus_existing")
    captured = with_memory_cache { with_checkout_stubs { service(company).call } }
    # El stub de Customer.create devolvería "cus_new" si se hubiera llamado.
    assert_equal "cus_existing", captured[:customer]
    assert_equal "cus_existing", company.reload.stripe_id
  end

  test "rejects a company that already has a paid subscription" do
    [ companies(:pro_co), companies(:past_due_co) ].each do |company|
      error = assert_raises(ApiErrors::UnprocessableEntityError) { service(company).call }
      assert_equal "subscription_already_active", error.details[:code]
    end
  end

  test "an active subscription without a Stripe id does not block the checkout" do
    company = companies(:one)
    company.subscription.update!(status: :active)
    assert_nothing_raised { with_memory_cache { with_checkout_stubs { service(company).call } } }
  end

  test "a trial or cancelled subscription may check out" do
    [ companies(:one), companies(:expired_co) ].each do |company|
      assert_nothing_raised { with_memory_cache { with_checkout_stubs { service(company).call } } }
    end
  end

  test "every plan and cycle is created with the IVA tax rate as the subscription default" do
    Plan.all.product(Plan::CYCLES).each do |plan, cycle|
      captured = with_memory_cache do
        with_checkout_stubs { service(companies(:expired_co), billing_cycle: cycle.to_s).call }
      end
      assert_equal [ "txr_iva_16" ], captured.dig(:subscription_data, :default_tax_rates), "#{plan.key} #{cycle}"
      assert_equal false, captured.dig(:automatic_tax, :enabled)
    end
  end

  test "the IVA rate and the remaining trial days travel together in subscription_data" do
    company = companies(:one)
    ends_at = company.subscription.trial_ends_at
    captured = with_memory_cache { with_checkout_stubs { service(company).call } }
    assert_equal({ default_tax_rates: [ "txr_iva_16" ], trial_end: ends_at.to_i }, captured[:subscription_data])
  end

  test "without the IVA tax rate in Stripe it fails closed and does not create customer or session" do
    company = companies(:one)
    error = nil
    captured = with_memory_cache do
      with_checkout_stubs(tax_rates: false) do
        error = assert_raises(ApiErrors::BadRequestError) { service(company).call }
      end
    end
    assert_equal I18n.t("errors.subscription.stripe_not_configured"), error.details
    assert_nil captured, "no debe crear la sesión de Checkout"
    # El stub de Customer.create guardaría "cus_new" si se hubiera llamado.
    assert_nil company.reload.stripe_id
  end

  test "an invalid plan raises bad request" do
    assert_raises(ApiErrors::BadRequestError) do
      with_memory_cache do
        with_checkout_stubs do
          Subscriptions::CreateCheckoutService.new(company: companies(:one), plan: "gold",
                                                   success_url: "a", cancel_url: "b").call
        end
      end
    end
  end
end
