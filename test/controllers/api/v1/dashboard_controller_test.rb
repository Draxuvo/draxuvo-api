require "test_helper"

# Contrato: specs/004-refactor-web-panel/contracts/api.md (GET /dashboard) y research.md R6.
# Cada número de una tarjeta es igual al info.total de la lista a la que enlaza.
class Api::V1::DashboardControllerTest < ActionDispatch::IntegrationTest
  MEXICO = ActiveSupport::TimeZone["America/Mexico_City"]

  setup do
    @company = companies(:pro_co)
    @owner = users(:pro_co_owner)
    @employee = @company.employees.create!(name: "Luis Pérez", position: "Técnico", status: :active)
  end

  test "low_stock counts stock <= min_stock, the same rule as the products list" do
    create_product("AGO-1", stock: 0, min_stock: 2)   # agotado y bajo
    create_product("BAJ-1", stock: 3, min_stock: 5)   # bajo
    create_product("BAJ-2", stock: 5, min_stock: 5)   # bajo (igual al mínimo)
    create_product("OK-1", stock: 10, min_stock: 5)   # suficiente
    create_product("OK-2", stock: 4, min_stock: 3)    # suficiente aunque sea <= 5
    create_product("NIL-1", stock: 2, min_stock: nil) # sin mínimo: no cuenta

    get "/api/v1/dashboard", headers: auth_headers(@owner, @company)

    assert_response :ok
    inventory = response.parsed_body["inventory"]
    assert_equal 6, inventory["total"]
    assert_equal 3, inventory["low_stock"]
    assert_equal 1, inventory["out_of_stock"]

    get "/api/v1/products", params: { low_stock: "true" }, headers: auth_headers(@owner, @company)
    assert_equal inventory["low_stock"], response.parsed_body.dig("info", "total")
  end

  test "out_of_stock counts products with stock 0" do
    create_product("AGO-1", stock: 0, min_stock: 2)
    create_product("AGO-2", stock: 0, min_stock: nil)
    create_product("OK-1", stock: 7, min_stock: 1)

    get "/api/v1/dashboard", headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal 2, response.parsed_body.dig("inventory", "out_of_stock")
  end

  test "attendance today uses the Mexico City day near midnight" do
    # 2026-10-14 23:30 en Ciudad de México = 2026-10-15 05:30 UTC.
    travel_to Time.utc(2026, 10, 15, 5, 30) do
      record(MEXICO.local(2026, 10, 14, 9, 0), :normal)   # hoy (15:00 UTC del 14)
      record(MEXICO.local(2026, 10, 14, 22, 0), :late)    # hoy (04:00 UTC del 15)
      record(MEXICO.local(2026, 10, 13, 21, 0), :absent)  # ayer (03:00 UTC del 14)

      get "/api/v1/dashboard", headers: auth_headers(@owner, @company)

      assert_response :ok
      today = response.parsed_body.dig("attendance", "today")
      assert_equal({ "total" => 2, "normal" => 1, "late" => 1, "absent" => 0 }, today)
    end
  end

  test "attendance this_month uses the Mexico City month" do
    # 2026-10-31 23:00 en Ciudad de México = 2026-11-01 05:00 UTC.
    travel_to Time.utc(2026, 11, 1, 5, 0) do
      record(MEXICO.local(2026, 10, 1, 8, 0), :normal)
      record(MEXICO.local(2026, 10, 31, 20, 0), :late)    # 02:00 UTC del 1 de noviembre
      record(MEXICO.local(2026, 10, 31, 21, 0), :normal)  # 03:00 UTC del 1 de noviembre
      record(MEXICO.local(2026, 9, 30, 19, 0), :normal)   # 01:00 UTC del 1 de octubre, mes pasado

      get "/api/v1/dashboard", headers: auth_headers(@owner, @company)

      assert_response :ok
      assert_equal 3, response.parsed_body.dig("attendance", "this_month")
    end
  end

  test "active_modules lists the company's active modules" do
    get "/api/v1/dashboard", headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal @company.active_modules.map(&:to_s).sort, response.parsed_body["active_modules"].sort
    assert_includes response.parsed_body["active_modules"], "attendance"
  end

  test "a disabled module drops out of active_modules and its section is zero" do
    create_product("AGO-1", stock: 0, min_stock: 2)
    @company.update!(disabled_modules: [ "inventory" ])

    get "/api/v1/dashboard", headers: auth_headers(@owner, @company)

    assert_response :ok
    body = response.parsed_body
    assert_not_includes body["active_modules"], "inventory"
    assert_equal 0, body.dig("inventory", "total")
    assert_equal 0, body.dig("inventory", "low_stock")
    assert_equal 0, body.dig("inventory", "out_of_stock")
  end

  test "work_orders to_charge counts done orders and tickets exclude voided from revenue" do
    get "/api/v1/dashboard", headers: auth_headers(@owner, @company)
    base = response.parsed_body["work_orders"]
    wo = ->(status, total) { @company.work_orders.create!(title: "Orden #{status}", employee: @employee, created_by: @owner, status: status, total: total) }
    wo.call(:done, 100)
    wo.call(:done, 50)
    paid_order = wo.call(:paid, 70)
    wo.call(:open, 10)

    get "/api/v1/dashboard", headers: auth_headers(@owner, @company)

    assert_response :ok
    orders = response.parsed_body["work_orders"]
    assert_equal base["to_charge"] + 2, orders["to_charge"]
    assert_equal base["to_charge_total"] + 150.0, orders["to_charge_total"]
    assert_equal base["by_status"]["done"] + 2, orders["by_status"]["done"]
    assert_equal base["by_status"]["paid"] + 1, orders["by_status"]["paid"]
    assert_equal %w[open in_progress done paid cancelled], orders["by_status"].keys
    assert_equal 0, response.parsed_body.dig("tickets", "voided")
    assert paid_order
  end

  private

  test "inventory adds the products and the value at cost by type (spec 016)" do
    create_product("BEB-1", stock: 4, min_stock: 0)
    @company.products.find_by!(sku: "BEB-1").update!(unit_cost: 10)
    @company.products.create!(name: "Servicio", sku: "SER-1", product_type: @company.product_types.find_by!(kind: "sold"), unit_cost: 99)

    get "/api/v1/dashboard", headers: auth_headers(@owner, @company)
    by_type = response.parsed_body.dig("inventory", "by_type").index_by { |row| row["name"] }
    assert_equal 1, by_type["Refacción"]["products"]
    assert_equal 40.0, by_type["Refacción"]["value"]
    assert_equal 1, by_type["Servicio"]["products"]
    assert_nil by_type["Servicio"]["value"]
  end

  def create_product(sku, stock:, min_stock:)
    # Un tipo que se cuenta (spec 016): solo esos tienen existencia, agotado y bajo inventario.
    counted = ProductTypes::Defaults.create_missing(@company).find_by!(kind: "counted_sold")
    @company.products.create!(name: "Producto #{sku}", sku: sku, stock: stock, min_stock: min_stock, product_type: counted)
  end

  def record(checkin_at, type)
    @company.attendances.create!(employee: @employee, checkin_at: checkin_at, attendance_type: type)
  end
end
