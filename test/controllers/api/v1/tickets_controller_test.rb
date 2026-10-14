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

  test "search with no match returns an empty page" do
    get "/api/v1/tickets", params: { search: "transmisión" }, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal 0, response.parsed_body.dig("info", "total")
    assert_empty response.parsed_body["results"]
  end

  test "search combines with status" do
    @oil.update!(status: :paid, paid_at: Time.current)
    @brakes.update!(status: :paid, paid_at: Time.current)

    get "/api/v1/tickets", params: { search: "frenos", status: "paid" }, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal [ @brakes.id ], ids
  end

  test "an invalid status is ignored" do
    get "/api/v1/tickets", params: { status: "foo" }, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal 3, response.parsed_body.dig("info", "total")
  end

  test "paginates with page and page_size" do
    get "/api/v1/tickets", params: { page: 1, page_size: 2 }, headers: auth_headers(@owner, @company)

    assert_response :ok
    info = response.parsed_body["info"]
    assert_equal({ "page_size" => 2, "page_index" => 1, "total" => 3, "page_start" => 1, "page_end" => 2, "pages_total" => 2 }, info)
    assert_equal 2, response.parsed_body["results"].size

    get "/api/v1/tickets", params: { page: 2, page_size: 2 }, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal 2, response.parsed_body.dig("info", "page_index")
    assert_equal 1, response.parsed_body["results"].size
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

  def create_ticket(title)
    order = @company.work_orders.create!(title: title, created_by: @owner)
    Ticket.create!(work_order: order, company: @company).reload
  end

  def ids
    response.parsed_body["results"].map { |t| t["id"] }
  end
end
