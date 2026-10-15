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
end
