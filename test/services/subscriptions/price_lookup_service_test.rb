require "test_helper"

class Subscriptions::PriceLookupServiceTest < ActiveSupport::TestCase
  test "resolves the price id by lookup key" do
    with_memory_cache do
      with_checkout_stubs do
        assert_equal "price_draxuvo_pro_monthly", Subscriptions::PriceLookupService.price_id(:pro, :monthly)
        assert_equal "price_draxuvo_enterprise_annual", Subscriptions::PriceLookupService.price_id("enterprise", "annual")
      end
    end
  end

  test "caches the price id so Stripe is called once" do
    with_memory_cache do |cache|
      calls = 0
      list = lambda do |*|
        calls += 1
        Stripe::ListObject.construct_from(object: "list",
          data: [ { id: "price_x", object: "price", lookup_key: "draxuvo_basic_monthly" } ])
      end
      Stripe::Price.stub(:list, list) do
        2.times { assert_equal "price_x", Subscriptions::PriceLookupService.price_id(:basic, :monthly) }
      end
      assert_equal 1, calls
      assert_equal "price_x", cache.read("stripe/price_id/draxuvo_basic_monthly")
    end
  end

  test "a missing price raises stripe_not_configured and is not cached" do
    with_memory_cache do |cache|
      with_checkout_stubs(prices: []) do
        error = assert_raises(ApiErrors::BadRequestError) do
          Subscriptions::PriceLookupService.price_id(:pro, :monthly)
        end
        assert_equal I18n.t("errors.subscription.stripe_not_configured"), error.details
      end
      assert_nil cache.read("stripe/price_id/draxuvo_pro_monthly")
    end
  end

  test "ignores prices whose lookup key does not match" do
    with_memory_cache do
      list = ->(*) { Stripe::ListObject.construct_from(object: "list", data: [ { id: "price_o", object: "price", lookup_key: "otra" } ]) }
      Stripe::Price.stub(:list, list) do
        assert_raises(ApiErrors::BadRequestError) { Subscriptions::PriceLookupService.price_id(:pro, :monthly) }
      end
    end
  end

  test "an unknown plan or cycle raises invalid_plan" do
    with_memory_cache do
      [ [ :gold, :monthly ], [ :pro, :weekly ] ].each do |plan, cycle|
        error = assert_raises(ApiErrors::BadRequestError) { Subscriptions::PriceLookupService.price_id(plan, cycle) }
        assert_equal I18n.t("errors.subscription.invalid_plan"), error.details
      end
    end
  end
end
