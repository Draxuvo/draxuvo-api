require "test_helper"

# Spec 039, FR-006b: las demos y sus usuarios no aparecen en lo interno (listas y conteos del super admin).
class Api::V1::DemoHiddenTest < ActionDispatch::IntegrationTest
  setup do
    @headers = auth_headers(users(:super_admin), companies(:pro_co))
    get "/api/v1/companies", params: { page_size: 100 }, headers: @headers
    @companies_before = response.parsed_body
    get "/api/v1/users", params: { page_size: 100 }, headers: @headers
    @users_before = response.parsed_body
    2.times { Demo::Provision.call(plan: "enterprise", scenario: "enterprise_restaurant", locale: "es") }
  end

  test "the company list and its total are the same with active demos" do
    get "/api/v1/companies", params: { page_size: 100 }, headers: @headers

    assert_response :ok
    assert_equal @companies_before["info"]["total"], response.parsed_body["info"]["total"]
    assert_equal @companies_before["results"].map { |c| c["id"] }, response.parsed_body["results"].map { |c| c["id"] }
    assert_operator Company.demo.count, :>=, 4, "las demos sí existen en la base"
  end

  test "the user list and its total are the same with active demos, even though their owners are owners" do
    get "/api/v1/users", params: { page_size: 100 }, headers: @headers

    assert_response :ok
    assert_equal @users_before["info"]["total"], response.parsed_body["info"]["total"]
    assert response.parsed_body["results"].none? { |user| user["email"].to_s.end_with?(".invalid") }
  end

  test "User.real and Company.real leave the demo ones out" do
    assert Company.real.none?(&:demo?)
    assert User.real.where("email LIKE '%@demo.invalid'").none?
    assert_equal Company.count - Company.demo.count, Company.real.count
  end

  test "the demo subscriptions never send billing notices" do
    demo = Company.demo.first
    Resend::Emails.stub(:send, ->(_params) { flunk "una demo mandó un aviso de cobro" }) do
      assert_equal false, Subscriptions::NotifyService.new(demo.subscription, "past_due").call
    end
  end
end
