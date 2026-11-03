require "test_helper"

# Spec 052: huecos del plan Básico (permisos del personal, usuario desactivado, intentos de login, datos imposibles).
class LaunchHardeningTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:basic_co) if companies(:basic_co)
    @owner = create_member(@company, role: :owner)
    @staff = create_member(@company, role: :staff)
    @oh = auth_headers(@owner, @company)
    @sh = auth_headers(@staff, @company)
  end

  test "staff gets 403 on employee records, team attendance, dashboard and company edits" do
    employee = @company.employees.first
    get "/api/v1/employees/#{employee.id}", headers: @sh
    assert_response :forbidden
    post "/api/v1/employees", params: { employee: { name: "X", salary: 1 } }, headers: @sh, as: :json
    assert_response :forbidden
    patch "/api/v1/employees/#{employee.id}", params: { employee: { salary: 1 } }, headers: @sh, as: :json
    assert_response :forbidden
    get "/api/v1/attendances", headers: @sh
    assert_response :forbidden
    get "/api/v1/attendances/roster", headers: @sh
    assert_response :forbidden
    get "/api/v1/dashboard", headers: @sh
    assert_response :forbidden
    patch "/api/v1/company", params: { company: { name: "Hackeada" } }, headers: @sh, as: :json
    assert_response :forbidden
    assert_not_equal "Hackeada", @company.reload.name
  end

  test "staff gets a minimal employee list without salary or contact data" do
    @company.employees.first.update!(salary: 9000, phone: "5512345678")
    get "/api/v1/employees", headers: @sh
    assert_response :ok
    row = response.parsed_body["results"].first
    assert_equal %w[id name status user_id], row.keys.sort
    get "/api/v1/employees", headers: @oh
    assert_equal 9000.0, response.parsed_body["results"].first["salary"].to_f
  end

  test "stripe_id is only shown to the owner" do
    @company.update!(stripe_id: "cus_secret")
    get "/api/v1/company", headers: @sh
    assert_not response.parsed_body.key?("stripe_id")
    get "/api/v1/company", headers: @oh
    assert_equal "cus_secret", response.parsed_body["stripe_id"]
  end

  test "a deactivated user loses access on the next request" do
    get "/api/v1/products", headers: @sh
    assert_response :ok
    @staff.update!(active: false)
    get "/api/v1/products", headers: @sh
    assert_response :unauthorized
    assert_equal I18n.t("auth.account_inactive"), response.parsed_body.dig("error", "message")
  end

  test "an exit larger than the stock is rejected with any body shape and the stock stays" do
    product = @company.products.create!(sku: "S-1", name: "Lápiz", stock: 4)
    post "/api/v1/products/#{product.id}/stock_movements", params: { stock_movement: { movement_type: "exit", qty: 50 } },
                                    headers: @oh, as: :json
    assert_response :unprocessable_entity
    post "/api/v1/products/#{product.id}/stock_movements", params: { movement_type: "exit", qty: 50 }, headers: @oh, as: :json
    assert_response :unprocessable_entity
    assert_equal 4, product.reload.stock
  end

  test "an invalid movement type or a zero quantity answers 422 and never 500" do
    product = @company.products.create!(sku: "S-2", name: "Goma", stock: 4)
    post "/api/v1/products/#{product.id}/stock_movements", params: { stock_movement: { movement_type: "nope", qty: 1 } },
                                    headers: @oh, as: :json
    assert_response :unprocessable_entity
    post "/api/v1/products/#{product.id}/stock_movements", params: { stock_movement: { movement_type: "entry", qty: 0 } },
                                    headers: @oh, as: :json
    assert_response :unprocessable_entity
    assert_no_match(/translation missing/i, response.body)
  end

  test "products reject negative or oversized numbers, long names and duplicated skus ignoring case" do
    base = { sku: "P-1", name: "Cuaderno" }
    [ { unit_cost: -1 }, { price: -5 }, { min_stock: -1 }, { stock: 10**15 }, { unit_cost: 10**15 },
      { name: "a" * 121 }, { sku: "s" * 61 } ].each do |bad|
      post "/api/v1/products", params: { product: base.merge(bad) }, headers: @oh, as: :json
      assert_response :unprocessable_entity, "#{bad.keys.first} should be rejected"
    end
    post "/api/v1/products", params: { product: base }, headers: @oh, as: :json
    assert_response :created
    post "/api/v1/products", params: { product: base.merge(sku: " p-1 ") }, headers: @oh, as: :json
    assert_response :unprocessable_entity
  end

  test "a product created with stock leaves an initial movement that is not an expense" do
    post "/api/v1/products", params: { product: { sku: "I-1", name: "Cartulina", stock: 10, unit_cost: 2 } }, headers: @oh, as: :json
    assert_response :created
    product = @company.products.find_by!(sku: "I-1")
    movement = product.stock_movements.sole
    assert movement.initial?
    assert_equal [ "entry", 10 ], [ movement.movement_type, movement.qty.to_i ]
    assert_equal @owner, movement.user
    assert_equal 10, product.reload.stock
    assert_equal product.stock, product.stock_movements.sum(:qty)
  end

  test "employees reject negative or huge salaries and phones with letters" do
    [ { salary: -1 }, { salary: 10**15 }, { phone: "abc123" }, { name: "n" * 121 } ].each do |bad|
      post "/api/v1/employees", params: { employee: { name: "Ana", salary: 100 }.merge(bad) }, headers: @oh, as: :json
      assert_response :unprocessable_entity, "#{bad.keys.first} should be rejected"
    end
  end

  test "reports answer 422 for an inverted range or a bad date" do
    get "/api/v1/reports/inventory", params: { from: "2026-02-01", to: "2026-01-01" }, headers: @oh
    assert_response :unprocessable_entity
    get "/api/v1/reports/inventory", params: { from: "no-es-fecha" }, headers: @oh
    assert_response :unprocessable_entity
    get "/api/v1/reports/summary", params: { period: "nope" }, headers: @oh
    assert_response :unprocessable_entity
    get "/api/v1/reports/inventory", params: { from: "2026-01-01", to: "2026-02-01" }, headers: @oh
    assert_response :ok
  end
end
