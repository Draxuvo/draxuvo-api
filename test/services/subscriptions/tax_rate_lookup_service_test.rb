require "test_helper"

class Subscriptions::TaxRateLookupServiceTest < ActiveSupport::TestCase
  def iva_rate(**overrides)
    { id: "txr_iva_16", object: "tax_rate", percentage: 16.0, inclusive: false, active: true,
      metadata: { draxuvo_tax: "iva_16" } }.merge(overrides)
  end

  def with_rates(*rates, &block)
    list = ->(*) { Stripe::ListObject.construct_from(object: "list", data: rates) }
    Stripe::TaxRate.stub(:list, list, &block)
  end

  test "resolves the IVA tax rate id by its metadata" do
    with_memory_cache do
      with_checkout_stubs { assert_equal "txr_iva_16", Subscriptions::TaxRateLookupService.tax_rate_id }
    end
  end

  test "caches the tax rate id so Stripe is called once" do
    with_memory_cache do |cache|
      calls = 0
      list = lambda do |*|
        calls += 1
        Stripe::ListObject.construct_from(object: "list", data: [ iva_rate ])
      end
      Stripe::TaxRate.stub(:list, list) do
        2.times { assert_equal "txr_iva_16", Subscriptions::TaxRateLookupService.tax_rate_id }
      end
      assert_equal 1, calls
      assert_equal "txr_iva_16", cache.read("stripe/tax_rate_id/iva_16")
    end
  end

  test "ignores rates without the metadata, with another percentage or already included in the price" do
    others = [
      iva_rate(id: "txr_no_metadata", metadata: {}),
      iva_rate(id: "txr_other_tag", metadata: { draxuvo_tax: "otra" }),
      iva_rate(id: "txr_eight", percentage: 8.0),
      iva_rate(id: "txr_inclusive", inclusive: true)
    ]
    with_memory_cache do
      with_rates(*others, iva_rate) { assert_equal "txr_iva_16", Subscriptions::TaxRateLookupService.tax_rate_id }
    end
  end

  test "a missing tax rate raises stripe_not_configured and is not cached" do
    with_memory_cache do |cache|
      with_rates(*[ iva_rate(percentage: 8.0) ]) do
        error = assert_raises(ApiErrors::BadRequestError) { Subscriptions::TaxRateLookupService.tax_rate_id }
        assert_equal I18n.t("errors.subscription.stripe_not_configured"), error.details
      end
      assert_nil cache.read("stripe/tax_rate_id/iva_16")
    end
  end
end
