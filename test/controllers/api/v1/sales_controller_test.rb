require "test_helper"

class Api::V1::SalesControllerTest < ActionDispatch::IntegrationTest
  BASE = "/api/v1/sales".freeze

  setup do
    @company = companies(:pos_co)
    @owner = users(:pos_owner)
    @admin = users(:pos_admin)
    @staff = users(:pos_staff)
    @staff2 = users(:pos_staff2)
    @cuaderno = products(:pos_cuaderno)
  end

  def headers(user, company = @company) = auth_headers(user, company)

  def json = response.parsed_body

  def code = json.dig("error", "details", "code")

  def create_sale(user = @staff)
    post BASE, headers: headers(user), as: :json
    assert_response :created
    json
  end

  def add(sale_id, user = @staff, **params)
    post "#{BASE}/#{sale_id}/items", params: params, headers: headers(user), as: :json
  end

  # --- módulo, suscripción y aislamiento ---

  test "without the pos module every action answers 403 module_not_in_plan" do
    owner = users(:pro_co_owner)
    get BASE, headers: headers(owner, companies(:pro_co))
    assert_response :forbidden
    assert_equal "module_not_in_plan", code
    assert_equal "pos", json.dig("error", "details", "module")

    post BASE, headers: headers(owner, companies(:pro_co)), as: :json
    assert_response :forbidden
    get "#{BASE}/catalog", headers: headers(owner, companies(:pro_co))
    assert_response :forbidden
  end

  test "an expired subscription blocks selling" do
    grant_addon!(companies(:expired_co), :pos) rescue nil
    get BASE, headers: headers(users(:expired_co_owner), companies(:expired_co))
    assert_response :forbidden
  end

  test "losing the module blocks the charge of an open sale" do
    sale = create_sale
    add(sale["id"], product_id: @cuaderno.id)
    @company.update!(disabled_modules: [ "pos" ])

    post "#{BASE}/#{sale["id"]}/charge", params: { lock_version: 2, payments: [ { method: "cash", amount_received: "100" } ] },
                                         headers: headers(@staff), as: :json
    assert_response :forbidden
    assert_equal "module_not_in_plan", code
    assert Sale.find(sale["id"]).status_open?
  end

  test "requires authentication" do
    get BASE
    assert_response :unauthorized
  end

  test "a sale of another company is not found" do
    other = Sale.create!(company: companies(:one), opened_by: users(:one_owner))
    get "#{BASE}/#{other.id}", headers: headers(@owner)
    assert_response :not_found
  end

  # --- abrir, ver y listar ---

  test "creating opens an empty sale of the cashier" do
    sale = create_sale
    assert_equal "open", sale["status"]
    assert_equal "0.00", sale["total"]
    assert_equal @staff.id, sale.dig("opened_by", "id")
    assert_equal [], sale["items"]
    assert_nil sale["ticket"]
    assert_equal %w[add_item charge discard], sale["actions"]
  end

  test "a cashier can have several open sales" do
    create_sale
    create_sale
    assert_equal 2, @company.sales.where(opened_by: @staff).count
  end

  test "staff only sees their own sales; owner and admin see all" do
    mine = create_sale(@staff)
    theirs = create_sale(@staff2)

    get BASE, headers: headers(@staff)
    assert_equal [ mine["id"] ], json["results"].map { |s| s["id"] }

    get BASE, headers: headers(@admin)
    assert_equal [ mine["id"], theirs["id"] ].sort, json["results"].map { |s| s["id"] }.sort

    get "#{BASE}/#{theirs["id"]}", headers: headers(@staff)
    assert_response :not_found
    get "#{BASE}/#{theirs["id"]}", headers: headers(@owner)
    assert_response :ok
  end

  test "list is paginated and filters by status, date, cashier and search" do
    paid = create_sale
    add(paid["id"], product_id: @cuaderno.id, quantity: 1)
    post "#{BASE}/#{paid["id"]}/charge", params: { lock_version: Sale.find(paid["id"]).lock_version,
                                                   payments: [ { method: "cash", amount_received: "50" } ] }, headers: headers(@staff), as: :json
    assert_response :ok
    open = create_sale(@staff2)

    get BASE, params: { status: "paid" }, headers: headers(@owner)
    assert_equal [ paid["id"] ], json["results"].map { |s| s["id"] }
    assert json["info"].present?

    get BASE, params: { status: "open", opened_by_id: @staff2.id }, headers: headers(@owner)
    assert_equal [ open["id"] ], json["results"].map { |s| s["id"] }

    get BASE, params: { search: "Cuaderno" }, headers: headers(@owner)
    assert_equal [ paid["id"] ], json["results"].map { |s| s["id"] }

    folio = Sale.find(paid["id"]).ticket.folio
    get BASE, params: { search: folio }, headers: headers(@owner)
    assert_equal [ paid["id"] ], json["results"].map { |s| s["id"] }

    get BASE, params: { from: 1.day.from_now.to_date.iso8601 }, headers: headers(@owner)
    assert_empty json["results"]
    get BASE, params: { to: 1.day.ago.to_date.iso8601 }, headers: headers(@owner)
    assert_empty json["results"]
  end

  test "opened_by_id is ignored for staff" do
    create_sale(@staff2)
    get BASE, params: { opened_by_id: @staff2.id }, headers: headers(@staff)
    assert_empty json["results"]
  end

  # --- renglones ---

  test "adding by product, barcode and sku builds the sale and totals it" do
    sale = create_sale
    add(sale["id"], product_id: @cuaderno.id, quantity: 2)
    assert_response :ok
    add(sale["id"], barcode: "7509990000028")
    add(sale["id"], sku: "SER-001", quantity: 4)

    assert_equal "100.00", json["total"]
    assert_equal 3, json["items"].size
    cuaderno = json["items"].find { |i| i["sku"] == "PAP-001" }
    assert_equal({ "name" => "Cuaderno profesional", "unit_price" => "42.50", "quantity" => 2, "subtotal" => "85.00", "stock" => 18 },
                 cuaderno.slice("name", "unit_price", "quantity", "subtotal", "stock"))
    assert_nil json["items"].find { |i| i["sku"] == "SER-001" }["stock"]
  end

  test "item errors carry their code" do
    sale = create_sale
    { products(:pos_resma) => "product_not_sellable", products(:pos_inactivo) => "product_inactive",
      products(:pos_sin_precio) => "product_without_price" }.each do |product, expected|
      add(sale["id"], product_id: product.id)
      assert_response :unprocessable_entity
      assert_equal expected, code
    end
    add(sale["id"], product_id: @cuaderno.id, quantity: 0)
    assert_equal "invalid_quantity", code
    add(sale["id"], barcode: "9999999999999")
    assert_response :not_found
    assert_equal "product_not_found", code
  end

  test "changing and removing items" do
    sale = create_sale
    add(sale["id"], product_id: @cuaderno.id)
    item_id = json["items"].first["id"]

    patch "#{BASE}/#{sale["id"]}/items/#{item_id}", params: { quantity: 3 }, headers: headers(@staff), as: :json
    assert_response :ok
    assert_equal "127.50", json["total"]

    delete "#{BASE}/#{sale["id"]}/items/#{item_id}", headers: headers(@staff)
    assert_response :ok
    assert_equal "0.00", json["total"]

    patch "#{BASE}/#{sale["id"]}/items/#{item_id}", params: { quantity: 1 }, headers: headers(@staff), as: :json
    assert_response :not_found
  end

  test "another cashier cannot touch my sale" do
    sale = create_sale(@staff)
    add(sale["id"], @staff2, product_id: @cuaderno.id)
    assert_response :not_found
    delete "#{BASE}/#{sale["id"]}", headers: headers(@staff2)
    assert_response :not_found
  end

  # --- descartar ---

  test "an open sale is discarded without touching stock; a paid one is not" do
    stock = @cuaderno.stock
    sale = create_sale
    add(sale["id"], product_id: @cuaderno.id)
    delete "#{BASE}/#{sale["id"]}", headers: headers(@staff)
    assert_response :no_content
    assert_nil Sale.find_by(id: sale["id"])
    assert_equal stock, @cuaderno.reload.stock

    paid = open_sale(@staff, [ @cuaderno, 1 ])
    charge_cash(paid)
    delete "#{BASE}/#{paid.id}", headers: headers(@admin)
    assert_response :unprocessable_entity
    assert_equal "not_open", code
  end

  # --- cobrar ---

  test "charging returns the paid sale with its ticket and the shortages" do
    sale = create_sale
    add(sale["id"], product_id: products(:pos_pluma).id, quantity: 5)
    post "#{BASE}/#{sale["id"]}/charge",
         params: { lock_version: json["lock_version"], payments: [ { method: "cash", amount_received: "50" } ] },
         headers: headers(@staff), as: :json

    assert_response :ok
    assert_equal "paid", json.dig("sale", "status")
    ticket = json.dig("sale", "ticket")
    assert_match(/\AT-/, ticket["folio"])
    assert_equal "cash", ticket["payment_method"]
    assert_equal 1, ticket["payments"].size
    assert_equal [ { "product_id" => products(:pos_pluma).id, "name" => "Pluma azul", "missing" => 2 } ], json["shortages"]
    assert_equal %w[ticket], json.dig("sale", "actions")
  end

  test "charging with a stale lock_version is a conflict" do
    sale = create_sale
    add(sale["id"], product_id: @cuaderno.id)
    post "#{BASE}/#{sale["id"]}/charge", params: { lock_version: 0, payments: [ { method: "cash", amount_received: "100" } ] },
                                        headers: headers(@staff), as: :json
    assert_response :conflict
    assert_equal "stale_object", code
  end

  test "charging errors" do
    sale = create_sale
    version = sale["lock_version"]
    pay = ->(payments) {
      post "#{BASE}/#{sale["id"]}/charge", params: { lock_version: version, payments: payments }, headers: headers(@staff), as: :json
    }
    pay.([ { method: "cash", amount_received: "10" } ])
    assert_response :unprocessable_entity
    assert_equal "empty", code

    add(sale["id"], product_id: @cuaderno.id)
    version = json["lock_version"]
    pay.([ { method: "cash", amount_received: "10" } ])
    assert_equal "missing", code
    pay.([ { method: "bitcoin", amount: "10" } ])
    assert_response :unprocessable_entity
  end

  test "the sale says whether the ticket can be sent by WhatsApp" do
    sale = create_sale
    assert_equal false, sale["whatsapp_available"]

    @company.billing_subscription.update!(plan: :enterprise)
    get "#{BASE}/#{sale["id"]}", headers: headers(@staff)
    assert_equal true, json["whatsapp_available"]
  end

  test "a boss can charge a sale opened by another cashier" do
    sale = open_sale(@staff2, [ @cuaderno, 1 ])
    post "#{BASE}/#{sale.id}/charge", params: { lock_version: sale.lock_version, payments: [ { method: "cash", amount_received: "50" } ] },
                                      headers: headers(@admin), as: :json
    assert_response :ok
    assert_equal @admin.id, json.dig("sale", "charged_by", "id")
    assert_equal @staff2.id, json.dig("sale", "opened_by", "id")
  end

  test "a ticket from a sale appears in the tickets serializer without breaking it" do
    sale = open_sale(@staff, [ @cuaderno, 1 ])
    ticket = charge_cash(sale).ticket
    data = TicketSerializer.new(ticket, detailed: true).as_json
    assert_equal sale.id, data[:sale][:id]
    assert_equal "Cuaderno profesional", data[:items].first[:description]
    assert_nil data[:work_order]
    assert_nil data[:check]
  end
end
