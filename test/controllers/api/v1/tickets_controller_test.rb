require "test_helper"

# Contrato: specs/004-refactor-web-panel/contracts/api.md (GET /tickets): search por folio o
# por título de la orden, status fuera del enum ignorado y paginación con info.
class Api::V1::TicketsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:pro_co)
    @owner = users(:pro_co_owner)
    @oil = create_ticket("Cambio de aceite")
    @brakes = create_ticket("Revisión de frenos")
    @alignment = create_ticket("Alineación y balanceo")
  end

  test "search matches the ticket folio" do
    get "/api/v1/tickets", params: { search: @brakes.folio }, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal [ @brakes.id ], ids
  end

  test "search matches the work order title, case insensitive" do
    get "/api/v1/tickets", params: { search: "FRENOS" }, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal [ @brakes.id ], ids
    assert_equal "Revisión de frenos", response.parsed_body["results"].first.dig("work_order", "title")
  end

  test "search matches the customer name" do
    @alignment.work_order.update!(customer_name: "Laura Méndez")

    get "/api/v1/tickets", params: { search: "laura" }, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal [ @alignment.id ], ids
  end

  test "status filter accepts voided" do
    @oil.update!(status: :voided, voided_at: Time.current, voided_by: @owner, void_reason: "Error")

    get "/api/v1/tickets", params: { status: "voided" }, headers: auth_headers(@owner, @company)

    assert_equal [ @oil.id ], ids
  end

  test "mark_as_paid no longer exists" do
    patch "/api/v1/tickets/#{@oil.id}/mark_as_paid", headers: auth_headers(@owner, @company)

    assert_response :not_found
  end

  test "staff only sees the tickets of their own orders" do
    staff = users(:pro_staff)
    employee = employees(:pro_staff_employee)
    @oil.work_order.update!(employee: employee)

    get "/api/v1/tickets", headers: auth_headers(staff, @company)
    assert_equal [ @oil.id ], ids

    get "/api/v1/tickets/#{@brakes.id}", headers: auth_headers(staff, @company)
    assert_response :not_found
  end

  test "staff without an employee sees no tickets" do
    get "/api/v1/tickets", headers: auth_headers(users(:pro_staff), @company)

    assert_response :ok
    assert_empty ids
  end

  test "send_whatsapp without phone param or order phone answers 400 with the i18n message" do
    company = companies(:enterprise_co)
    owner = users(:enterprise_co_owner)
    order = company.work_orders.create!(title: "Sin teléfono", created_by: owner)
    ticket = Ticket.create!(work_order: order, company: company)

    post "/api/v1/tickets/#{ticket.id}/send_whatsapp", headers: auth_headers(owner, company), as: :json

    assert_response :bad_request
    assert_equal I18n.t("ticket.phone_required"), response.parsed_body.dig("error", "details")
  end

  test "send_whatsapp without WhatsApp configured answers 422 with a clear message, not 500" do
    company = companies(:enterprise_co)
    owner = users(:enterprise_co_owner)
    order = company.work_orders.create!(title: "Con teléfono", created_by: owner, customer_phone: "5512345678")
    ticket = Ticket.create!(work_order: order, company: company)

    with_env("WHATSAPP_ACCESS_TOKEN" => nil, "WHATSAPP_PHONE_NUMBER_ID" => nil) do
      post "/api/v1/tickets/#{ticket.id}/send_whatsapp", headers: auth_headers(owner, company), as: :json
    end

    assert_response :unprocessable_entity
    assert_equal I18n.t("whatsapp.not_configured"), response.parsed_body.dig("error", "details")
    assert_not_includes response.body, "WHATSAPP_"
  end

  test "search with no match returns an empty page" do
    get "/api/v1/tickets", params: { search: "transmisión" }, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal 0, response.parsed_body.dig("info", "total")
    assert_empty response.parsed_body["results"]
  end

  test "search combines with status" do
    pay(@oil)
    pay(@brakes)

    get "/api/v1/tickets", params: { search: "frenos", status: "paid" }, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal [ @brakes.id ], ids
  end

  test "an invalid status is ignored" do
    get "/api/v1/tickets", params: { status: "foo" }, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal 4, response.parsed_body.dig("info", "total")
  end

  test "paginates with page and page_size" do
    get "/api/v1/tickets", params: { page: 1, page_size: 2 }, headers: auth_headers(@owner, @company)

    assert_response :ok
    info = response.parsed_body["info"]
    assert_equal({ "page_size" => 2, "page_index" => 1, "total" => 4, "page_start" => 1, "page_end" => 2, "pages_total" => 2 }, info)
    assert_equal 2, response.parsed_body["results"].size

    get "/api/v1/tickets", params: { page: 2, page_size: 2 }, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal 2, response.parsed_body.dig("info", "page_index")
    assert_equal 2, response.parsed_body["results"].size
  end

  test "another company's tickets are not found by search" do
    other_company = companies(:enterprise_co)
    other_order = other_company.work_orders.create!(title: "Revisión de frenos ajena", created_by: users(:enterprise_co_owner))
    Ticket.create!(work_order: other_order, company: other_company)

    get "/api/v1/tickets", params: { search: "frenos" }, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal [ @brakes.id ], ids
  end

  private

  def pay(ticket)
    ticket.update!(status: :paid, paid_at: Time.current, payment_method: :cash,
                   amount_received: ticket.total, charged_by: @owner)
  end

  def create_ticket(title)
    order = @company.work_orders.create!(title: title, created_by: @owner)
    Ticket.create!(work_order: order, company: @company).reload
  end

  def ids
    response.parsed_body["results"].map { |t| t["id"] }
  end

  # Tickets de cuentas de restaurante (spec 013, FR-025).
  def resto_get(path, user, params = {})
    get path, params: params, headers: auth_headers(user, companies(:resto_co))
  end

  test "a restaurant ticket lists with its check and without a work order" do
    resto_get("/api/v1/tickets", users(:resto_owner))

    assert_response :ok
    ticket = response.parsed_body["results"].find { |t| t["folio"] == "T-900050" }
    assert_nil ticket["work_order"]
    assert_equal "2", ticket.dig("check", "table")
    assert_equal "cash", ticket["payment_method"]
  end

  test "the detail lists what was sold and each payment" do
    resto_get("/api/v1/tickets/#{tickets(:resto_paid_ticket).id}", users(:resto_owner))

    assert_response :ok
    body = response.parsed_body
    assert_equal [ "Tacos al pastor" ], body["items"].map { |i| i["description"] }
    assert_equal [ [ "cash", "70.00", "100.00", "30.00" ] ],
                 body["payments"].map { |p| p.values_at("method", "amount", "amount_received", "change_given") }
    assert_equal users(:resto_waiter).id, body.dig("check", "waiter", "id")
  end

  test "a waiter sees only the tickets of their own checks" do
    resto_get("/api/v1/tickets", users(:resto_waiter))
    assert_equal [ "T-900050" ], response.parsed_body["results"].map { |t| t["folio"] }

    resto_get("/api/v1/tickets", users(:resto_waiter2))
    assert_empty response.parsed_body["results"]
  end

  test "a waiter cannot open the ticket of someone else's check" do
    resto_get("/api/v1/tickets/#{tickets(:resto_paid_ticket).id}", users(:resto_waiter2))

    assert_response :not_found
  end

  test "search finds a restaurant ticket by table or takeout name" do
    resto_get("/api/v1/tickets", users(:resto_owner), search: "2")
    assert_includes response.parsed_body["results"].map { |t| t["folio"] }, "T-900050"

    takeout = checks(:takeout_check)
    Ticket.create!(check: takeout, company: takeout.company, status: :paid, total: 0, paid_at: Time.current,
                   payment_method: :cash, amount_received: 0, charged_by: users(:resto_owner))
    resto_get("/api/v1/tickets", users(:resto_owner), search: "luis")
    assert_equal 1, response.parsed_body["results"].size
  end

  test "the PDF of a restaurant ticket downloads" do
    resto_get("/api/v1/tickets/#{tickets(:resto_paid_ticket).id}/download", users(:resto_owner))

    assert_response :ok
    assert_equal "application/pdf", response.media_type
    assert response.body.b.start_with?("%PDF")
  end
end
