require "test_helper"

class Subscriptions::PriceLookupServiceAddonTest < ActiveSupport::TestCase
  test "finds the Stripe price of an add-on by its lookup key" do
    with_memory_cache do
      with_addon_stubs do
        assert_equal "price_draxuvo_addon_pos_monthly", Subscriptions::PriceLookupService.addon_price_id(:pos, :monthly)
        assert_equal "price_draxuvo_addon_pos_annual", Subscriptions::PriceLookupService.addon_price_id("pos", "annual")
      end
    end
  end

  test "a missing price is a stripe_not_configured error" do
    with_memory_cache do
      with_addon_stubs(prices: []) do
        error = assert_raises(ApiErrors::BadRequestError) { Subscriptions::PriceLookupService.addon_price_id(:pos, :monthly) }
        assert_equal I18n.t("errors.subscription.stripe_not_configured"), error.details
      end
    end
  end

  test "an unknown add-on or cycle is a bad request" do
    with_memory_cache do
      with_addon_stubs do
        assert_raises(ApiErrors::BadRequestError) { Subscriptions::PriceLookupService.addon_price_id(:nada, :monthly) }
        assert_raises(ApiErrors::BadRequestError) { Subscriptions::PriceLookupService.addon_price_id(:pos, :weekly) }
      end
    end
  end

  test "plan prices keep working" do
    with_memory_cache do
      with_addon_stubs { assert_equal "price_draxuvo_pro_monthly", Subscriptions::PriceLookupService.price_id(:pro, :monthly) }
    end
  end
end
