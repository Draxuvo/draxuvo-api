require "test_helper"

class Subscriptions::PortalServiceTest < ActiveSupport::TestCase
  test "returns the portal url for a company with a billing account" do
    company = companies(:pro_co)
    company.update_column(:stripe_id, "cus_pro")
    captured = nil
    session = Stripe::StripeObject.construct_from(url: "https://billing.stripe.com/p/session/x")
    Stripe::BillingPortal::Session.stub(:create, ->(params, *) { captured = params; session }) do
      result = Subscriptions::PortalService.new(company: company, return_url: "https://app.test/facturacion").call
      assert_equal({ portal_url: "https://billing.stripe.com/p/session/x" }, result)
    end
    assert_equal({ customer: "cus_pro", return_url: "https://app.test/facturacion" }, captured)
  end

  test "rejects a company without a billing account" do
    Stripe::BillingPortal::Session.stub(:create, ->(*) { flunk "should not call Stripe" }) do
      error = assert_raises(ApiErrors::UnprocessableEntityError) do
        Subscriptions::PortalService.new(company: companies(:pro_co), return_url: "https://app.test").call
      end
      assert_equal "no_billing_account", error.details[:code]
    end
  end

  test "a blank stripe id counts as no billing account" do
    company = companies(:pro_co)
    company.update_column(:stripe_id, "")
    assert_raises(ApiErrors::UnprocessableEntityError) do
      Subscriptions::PortalService.new(company: company, return_url: "https://app.test").call
    end
  end
end
