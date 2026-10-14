require "test_helper"

# Contrato: specs/004-refactor-web-panel/contracts/api.md ("/company/branches" y cobro en sucursales).
# FR-027, FR-028, FR-029. Stripe siempre se simula: una sucursal nunca debe llegar a él.
class Api::V1::BranchesControllerTest < ActionDispatch::IntegrationTest
  BASE = "/api/v1/company/branches".freeze
  SUBSCRIPTION = "/api/v1/subscription".freeze

  setup do
    @main = companies(:enterprise_co)
    @owner = users(:enterprise_co_owner)
  end

  test "the owner of an enterprise main company creates a branch and becomes its owner" do
    assert_no_difference "Subscription.count" do
      assert_difference "Company.count", 1 do
        post BASE, params: { branch: { name: "Sucursal Norte" } }, headers: auth_headers(@owner, @main), as: :json
      end
    end

    assert_response :created
    branch = Company.find(json.dig("company", "id"))
    assert_equal @main.id, json.dig("company", "parent_company_id")
    assert_equal "Sucursal Norte", json.dig("company", "name")
    assert json.dig("company", "slug").present?
    assert_equal @main, branch.parent
    assert_nil branch.subscription
    assert_equal "owner", @owner.user_companies.find_by!(company: branch).role

    listed = json.dig("user", "companies").find { |c| c["id"] == branch.id }
    assert_equal "owner", listed["role"]
    assert_equal @main.id, listed["parent_company_id"]
  end

  test "a branch uses the subscription and modules of its main company" do
    branch = create_branch

    get SUBSCRIPTION, headers: auth_headers(@owner, branch)
    assert_response :ok
    assert_equal subscriptions(:enterprise_co).id, json["id"]
    assert_equal "enterprise", json["plan"]
    assert_equal true, json["managed_by_parent"]

    get SUBSCRIPTION, headers: auth_headers(@owner, @main)
    assert_equal false, json["managed_by_parent"]

    get "/api/v1/work_orders", headers: auth_headers(@owner, branch)
    assert_response :ok
  end

  test "the limit is 3 companies in total" do
    2.times do |i|
      post BASE, params: { branch: { name: "Sucursal #{i}" } }, headers: auth_headers(@owner, @main), as: :json
      assert_response :created
    end

    assert_no_difference "Company.count" do
      post BASE, params: { branch: { name: "Una de más" } }, headers: auth_headers(@owner, @main), as: :json
    end
    assert_response :unprocessable_entity
    assert_equal "company_limit_reached", json.dig("error", "details", "code")
  end

  test "a pro company gets 403 module_not_in_plan" do
    assert_no_difference "Company.count" do
      post BASE, params: { branch: { name: "Sucursal" } }, headers: auth_headers(users(:pro_co_owner)), as: :json
    end

    assert_response :forbidden
    assert_equal "module_not_in_plan", json.dig("error", "details", "code")
    assert_equal "multi_company", json.dig("error", "details", "module")
  end

  test "only the owner creates branches" do
    admin = create_member(@main, role: :admin)

    assert_no_difference "Company.count" do
      post BASE, params: { branch: { name: "Sucursal" } }, headers: auth_headers(admin, @main), as: :json
    end
    assert_response :forbidden
  end

  test "a branch cannot create branches" do
    branch = create_branch

    assert_no_difference "Company.count" do
      post BASE, params: { branch: { name: "Nieta" } }, headers: auth_headers(@owner, branch), as: :json
    end
    assert_response :unprocessable_entity
    assert_equal "not_a_main_company", json.dig("error", "details", "code")
  end

  test "index lists the main company and its branches, also from a branch" do
    branch = create_branch

    [ @main, branch ].each do |active|
      get BASE, headers: auth_headers(@owner, active)

      assert_response :ok
      assert_equal [ @main.id, branch.id ], json.map { |c| c["id"] }
      assert_equal [ nil, @main.id ], json.map { |c| c["parent_company_id"] }
    end
  end

  test "billing actions on a branch answer 422 billing_managed_by_parent" do
    branch = create_branch
    headers = auth_headers(@owner, branch)
    guard = ->(*) { flunk "Stripe should not be called" }

    Stripe::Checkout::Session.stub(:create, guard) do
      Stripe::BillingPortal::Session.stub(:create, guard) do
        Stripe::Subscription.stub(:update, guard) do
          post "#{SUBSCRIPTION}/checkout", params: { plan: "pro", billing_cycle: "monthly",
                                                     success_url: "https://ui.test/ok", cancel_url: "https://ui.test/no" },
                                           headers: headers, as: :json
          assert_billing_managed_by_parent "checkout"

          post "#{SUBSCRIPTION}/portal", params: { return_url: "https://ui.test/es/suscripcion" }, headers: headers, as: :json
          assert_billing_managed_by_parent "portal"

          patch SUBSCRIPTION, params: { plan: "basic" }, headers: headers, as: :json
          assert_billing_managed_by_parent "PATCH"

          delete SUBSCRIPTION, headers: headers
          assert_billing_managed_by_parent "DELETE"
        end
      end
    end

    assert_equal "enterprise", subscriptions(:enterprise_co).reload.plan
  end

  test "a branch is blocked without deleting data when the main company loses multi_company" do
    branch = create_branch
    product = branch.products.create!(name: "Tornillo", sku: "TOR-1", stock: 3)

    subscriptions(:enterprise_co).update!(plan: :pro)
    get "/api/v1/employees", headers: auth_headers(@owner, branch)

    assert_response :forbidden
    assert_equal "module_not_in_plan", json.dig("error", "details", "code")
    assert_equal "multi_company", json.dig("error", "details", "module")
    assert Product.exists?(product.id)
    assert Company.exists?(branch.id)

    get "/api/v1/employees", headers: auth_headers(@owner, @main)
    assert_response :ok
  end

  private

  def create_branch(name: "Sucursal Centro")
    post BASE, params: { branch: { name: name } }, headers: auth_headers(@owner, @main), as: :json
    assert_response :created
    Company.find(json.dig("company", "id"))
  end

  def assert_billing_managed_by_parent(action)
    assert_response :unprocessable_entity, action
    assert_equal "billing_managed_by_parent", json.dig("error", "details", "code"), action
  end

  def json
    JSON.parse(response.body)
  end
end
