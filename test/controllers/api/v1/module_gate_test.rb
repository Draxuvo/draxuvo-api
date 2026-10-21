require "test_helper"

# Contrato: specs/002-rebrand-suscripciones/contracts/api.md (403 module_not_in_plan) y data-model.md
# (tabla de módulos). Cada plan da sus módulos; los demás responden 403 sin borrar datos (FR-024, FR-025).
class Api::V1::ModuleGateTest < ActionDispatch::IntegrationTest
  PRO_ONLY = {
    "work_orders" => "/api/v1/work_orders",
    "tickets" => "/api/v1/tickets",
    "reports" => "/api/v1/reports/summary",
    "terminals" => "/api/v1/payment_terminals"
  }.freeze

  BASIC = {
    "employees" => "/api/v1/employees",
    "attendance" => "/api/v1/attendances",
    "inventory" => "/api/v1/products"
  }.freeze

  test "a basic company gets 403 module_not_in_plan on work orders, tickets and reports" do
    PRO_ONLY.each do |module_key, path|
      get path, headers: auth_headers(users(:basic_co_owner))

      assert_response :forbidden, "#{path} should be blocked for basic"
      assert_module_blocked module_key
    end
  end

  test "a basic company can use its own modules" do
    (BASIC.values + [ "/api/v1/units" ]).each do |path|
      get path, headers: auth_headers(users(:basic_co_owner))

      assert_response :ok, "#{path} should be allowed for basic"
    end
  end

  test "a pro company can use work orders, tickets and reports" do
    PRO_ONLY.each_value do |path|
      get path, headers: auth_headers(users(:pro_co_owner))

      assert_response :ok, "#{path} should be allowed for pro"
    end
  end

  test "inventory gates products, units and stock movements" do
    company = companies(:pro_co)
    company.update!(disabled_modules: [ "inventory" ])
    product = company.products.create!(name: "Tornillo", sku: "TOR-1", stock: 3)

    [ "/api/v1/products", "/api/v1/units", "/api/v1/products/#{product.id}/stock_movements" ].each do |path|
      get path, headers: auth_headers(users(:pro_co_owner))

      assert_response :forbidden, "#{path} should be blocked"
      assert_module_blocked "inventory"
    end
  end

  test "employee checkin and checkout are gated by attendance, the CRUD by employees" do
    company = companies(:pro_co)
    employee = company.employees.create!(name: "Ana", position: "Técnica")
    company.update!(disabled_modules: [ "attendance" ])

    post "/api/v1/employees/#{employee.id}/checkin", headers: auth_headers(users(:pro_co_owner))
    assert_response :forbidden
    assert_module_blocked "attendance"

    get "/api/v1/employees", headers: auth_headers(users(:pro_co_owner))
    assert_response :ok

    company.update!(disabled_modules: [ "employees" ])
    get "/api/v1/employees", headers: auth_headers(users(:pro_co_owner))
    assert_response :forbidden
    assert_module_blocked "employees"
  end

  test "a module disabled by the company answers 403" do
    companies(:pro_co).update!(disabled_modules: [ "work_orders" ])

    get "/api/v1/work_orders", headers: auth_headers(users(:pro_co_owner))

    assert_response :forbidden
    assert_module_blocked "work_orders"

    get "/api/v1/tickets", headers: auth_headers(users(:pro_co_owner))
    assert_response :ok
  end

  test "whatsapp is only available on enterprise" do
    ticket = create_ticket(companies(:pro_co), users(:pro_co_owner))

    post "/api/v1/tickets/#{ticket.id}/send_whatsapp", params: { phone: "5512345678" },
                                                        headers: auth_headers(users(:pro_co_owner)), as: :json

    assert_response :forbidden
    assert_module_blocked "whatsapp"
  end

  test "the super admin is never blocked by modules" do
    get "/api/v1/work_orders", headers: auth_headers(users(:super_admin), companies(:basic_co))

    assert_response :ok
  end

  test "downgrading the plan keeps the data and unlocks it again on upgrade" do
    company = companies(:pro_co)
    order = company.work_orders.create!(title: "Revisión", created_by: users(:pro_co_owner))

    subscriptions(:pro_co).update!(plan: :basic)
    get "/api/v1/work_orders", headers: auth_headers(users(:pro_co_owner))

    assert_response :forbidden
    assert_module_blocked "work_orders"
    assert WorkOrder.exists?(order.id), "downgrade must not delete data"

    subscriptions(:pro_co).update!(plan: :pro)
    get "/api/v1/work_orders", headers: auth_headers(users(:pro_co_owner))

    assert_response :ok
    assert_includes json["results"].map { |o| o["id"] }, order.id
  end

  test "the dashboard keeps its keys but zeroes inactive modules without hiding active ones" do
    company = companies(:basic_co)
    company.work_orders.create!(title: "Antes del downgrade", created_by: users(:basic_co_owner))
    company.products.create!(name: "Tuerca", sku: "TUE-1", stock: 4)

    get "/api/v1/dashboard", headers: auth_headers(users(:basic_co_owner))

    assert_response :ok
    body = json
    %w[employees users work_orders tickets inventory attendance].each do |key|
      assert body.key?(key), "missing #{key}"
    end
    assert_equal 0, body["work_orders"]["total"]
    assert_equal 0, body["work_orders"]["by_status"]["open"]
    assert_equal 0, body["work_orders"]["to_charge"]
    assert_equal 0.0, body["work_orders"]["to_charge_total"]
    assert_equal 0, body["tickets"]["total"]
    assert_equal 1, body["inventory"]["total"]
    assert_equal %w[employees attendance inventory], body["active_modules"]
  end

  test "the dashboard includes every section for pro" do
    get "/api/v1/dashboard", headers: auth_headers(users(:pro_co_owner))

    assert_response :ok
    %w[employees users work_orders tickets inventory attendance].each do |key|
      assert_not_nil json[key], "#{key} should be present for pro"
    end
    assert_includes json["active_modules"], "work_orders"
  end

  private

  def assert_module_blocked(module_key)
    details = json.dig("error", "details")
    assert_equal "module_not_in_plan", details["code"]
    assert_equal module_key, details["module"]
  end

  def create_ticket(company, user)
    order = company.work_orders.create!(title: "Servicio", created_by: user)
    Ticket.create!(work_order: order, company: company)
  end

  def json
    JSON.parse(response.body)
  end
end
