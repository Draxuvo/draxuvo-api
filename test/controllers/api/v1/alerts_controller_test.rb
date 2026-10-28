require "test_helper"

# Contrato: specs/045-alertas-operativas/contracts/api.md (GET /alerts). Solo dueño y administrador.
class Api::V1::AlertsControllerTest < ActionDispatch::IntegrationTest
  PATH = "/api/v1/alerts".freeze

  setup do
    @company = companies(:resto_co)
    @owner = create_member(@company, role: :owner)
    Product.where(company_id: @company.id).update_all(stock: 1000) # que el stock bajo no mezcle las cuentas
    KitchenOrder.where(id: kitchen_orders(:first_round).id).update_all(sent_at: 15.minutes.ago)
  end

  def json = JSON.parse(response.body)

  test "the owner gets the active alerts with the paginated shape plus count and snoozed" do
    get PATH, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal %w[count info results snoozed], json.keys.sort
    assert_equal 1, json["count"]
    assert_equal 1, json["info"]["total"]
    assert_equal [], json["snoozed"]
    alert = json["results"].first
    assert_equal "kitchen_wait", alert["kind"]
    assert_equal "warning", alert["severity"]
    assert_equal "Mesa 1 · Comanda #1 · Cocina", alert["subject"]["label"]
    assert_equal({ "type" => "station", "name" => "Cocina" }, alert["owner"])
  end

  test "admin and super admin can read it, staff cannot" do
    admin = create_member(@company, role: :admin)
    get PATH, headers: auth_headers(admin, @company)
    assert_response :ok

    get PATH, headers: auth_headers(users(:super_admin), @company)
    assert_response :ok

    waiter = create_member(@company, role: :staff)
    get PATH, headers: auth_headers(waiter, @company)
    assert_response :forbidden
  end

  test "it requires a session" do
    get PATH
    assert_response :unauthorized
  end

  test "alerts are scoped to the active company" do
    other_owner = create_member(companies(:pro_co), role: :owner)
    get PATH, headers: auth_headers(other_owner, companies(:pro_co))

    assert_response :ok
    assert_equal 0, json["count"]
    assert_empty json["results"]
  end

  test "a branch has its own alerts" do
    branch = Company.create!(name: "Sucursal Alertas", parent: companies(:enterprise_co))
    owner = create_member(branch, role: :owner)
    get PATH, headers: auth_headers(owner, branch)

    assert_response :ok
    assert_equal 0, json["count"]
  end

  test "alert types of modules that are off do not appear" do
    @company.update!(disabled_modules: [ "restaurant" ])
    get PATH, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal 0, json["count"]
  end

  test "it paginates like the other lists and clamps a page that is too high" do
    Station.where(id: stations(:bar).id).update_all(kind: "bar")
    CheckItem.where(id: check_items(:item_ready).id).update_all(status: 1)

    get PATH, params: { page_size: 1 }, headers: auth_headers(@owner, @company)
    assert_response :ok
    assert_equal 2, json["count"]
    assert_equal 1, json["results"].size
    assert_equal [ 1, 2, 1 ], json["info"].values_at("page_size", "total", "page_index").then { |size, total, index| [ size, total, index ] }
    assert_equal 2, json["info"]["pages_total"]

    get PATH, params: { page_size: 1, page: 99 }, headers: auth_headers(@owner, @company)
    assert_response :ok
    assert_equal 2, json["info"]["page_index"]
    assert_equal 1, json["results"].size
    assert_equal [], json["snoozed"]
  end

  test "a page size above the maximum is capped" do
    get PATH, params: { page_size: 5000 }, headers: auth_headers(@owner, @company)
    assert_equal 100, json["info"]["page_size"]
  end
end
