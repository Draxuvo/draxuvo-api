require "test_helper"
require "stringio"

# Contrato: specs/007-ordenes-simples/contracts/api.md. Staff solo ve y actúa sobre sus órdenes (FR-009 a FR-012).
class Api::V1::WorkOrdersStaffTest < ActionDispatch::IntegrationTest
  BASE = "/api/v1/work_orders".freeze

  setup do
    @company = companies(:pro_co)
    @staff = users(:pro_staff)
    @headers = auth_headers(@staff, @company)
    @mine = work_orders(:pro_open)
    @started = work_orders(:pro_started)
    @foreign = work_orders(:pro_done)
  end

  PNG_BYTES = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")

  def png_upload(name = "foto.png", type = "image/png", size = nil, bytes: nil)
    bytes ||= size ? PNG_BYTES + ("\0" * size) : PNG_BYTES
    Rack::Test::UploadedFile.new(StringIO.new(bytes), type, original_filename: name)
  end

  test "lists only the orders assigned to the staff employee" do
    get BASE, headers: @headers
    assert_response :ok
    ids = response.parsed_body["results"].map { |o| o["id"] }
    assert_equal [ @mine.id, @started.id ].sort, ids.sort
    assert_not_includes ids, @foreign.id
    assert_not_includes ids, work_orders(:pro_unassigned).id
  end

  test "an order of another employee answers 404 for every action" do
    get "#{BASE}/#{@foreign.id}", headers: @headers
    assert_response :not_found

    %w[start finish reopen cancel charge void_charge].each do |action|
      post "#{BASE}/#{@foreign.id}/#{action}", headers: @headers, as: :json
      assert_response :not_found, action
    end
    post "#{BASE}/#{@foreign.id}/notes", params: { text: "hola" }, headers: @headers, as: :json
    assert_response :not_found
    assert_equal "done", @foreign.reload.status
  end

  test "a staff user without an employee in the company sees nothing" do
    other = create_member(@company, role: :staff)
    get BASE, headers: auth_headers(other, @company)
    assert_response :ok
    assert_empty response.parsed_body["results"]

    get "#{BASE}/#{@mine.id}", headers: auth_headers(other, @company)
    assert_response :not_found
  end

  test "a person who is owner of one company and staff of another is scoped per company" do
    multi = create_member(companies(:one), role: :owner)
    UserCompany.create!(user: multi, company: @company, role: :staff)
    get BASE, headers: auth_headers(multi, @company)
    assert_response :ok
    assert_empty response.parsed_body["results"]

    get "#{BASE}/#{work_orders(:one_order).id}", headers: auth_headers(multi, companies(:one))
    assert_response :ok
  end

  test "staff starts, checks steps, adds a note and finishes with pending steps" do
    post "#{BASE}/#{@mine.id}/start", headers: @headers, as: :json
    assert_response :ok
    assert_equal "in_progress", response.parsed_body["status"]

    step = work_order_steps(:pro_open_step_1)
    patch "#{BASE}/#{@mine.id}/steps/#{step.id}", params: { done: true }, headers: @headers, as: :json
    assert_response :ok
    assert_equal 1, response.parsed_body["steps_done"]

    post "#{BASE}/#{@mine.id}/notes", params: { text: "Falta el cable" }, headers: @headers, as: :json
    assert_response :created

    post "#{BASE}/#{@mine.id}/finish", headers: @headers, as: :json
    assert_response :ok
    assert_equal "done", response.parsed_body["status"]
    finished = response.parsed_body["events"].find { |e| e["kind"] == "finished" }
    assert_equal 1, finished.dig("data", "pending_steps")
    assert_equal @staff.full_name, finished.dig("actor", "name")
  end

  test "staff adds and removes photos with type size and limit rules" do
    post "#{BASE}/#{@mine.id}/photos", params: { file: png_upload }, headers: @headers
    assert_response :created
    photo_id = response.parsed_body["photos"].first["id"]

    post "#{BASE}/#{@mine.id}/photos", params: { file: png_upload("a.pdf", "application/pdf", bytes: "%PDF-1.4\n%fake") }, headers: @headers
    assert_response :unprocessable_entity

    post "#{BASE}/#{@mine.id}/photos", params: { file: png_upload("big.png", "image/png", 11.megabytes) }, headers: @headers
    assert_response :unprocessable_entity

    9.times { post "#{BASE}/#{@mine.id}/photos", params: { file: png_upload }, headers: @headers }
    post "#{BASE}/#{@mine.id}/photos", params: { file: png_upload }, headers: @headers
    assert_response :unprocessable_entity, "la foto 11 se rechaza"

    delete "#{BASE}/#{@mine.id}/photos/#{photo_id}", headers: @headers
    assert_response :ok
  end

  test "staff charges an assigned finished order" do
    order = work_orders(:pro_done)
    order.update_columns(employee_id: employees(:pro_staff_employee).id)

    post "#{BASE}/#{order.id}/charge", params: { payment_method: "cash", amount_received: 900 }, headers: @headers, as: :json
    assert_response :ok
    assert_equal "paid", response.parsed_body["status"]
    ticket = response.parsed_body["ticket"]
    assert_equal "50.0", ticket["change_given"].to_s
    assert_equal @staff.full_name, ticket.dig("charged_by", "name")
  end

  test "staff cannot cancel void delete reassign create or change prices" do
    post "#{BASE}/#{@mine.id}/cancel", params: { reason: "x" }, headers: @headers, as: :json
    assert_response :forbidden

    post "#{BASE}/#{@mine.id}/void_charge", params: { reason: "x" }, headers: @headers, as: :json
    assert_response :forbidden

    delete "#{BASE}/#{@mine.id}", headers: @headers
    assert_response :forbidden

    patch "#{BASE}/#{@mine.id}", params: { work_order: { employee_id: employees(:pro_other_employee).id } }, headers: @headers, as: :json
    assert_response :forbidden
    assert_equal employees(:pro_staff_employee).id, @mine.reload.employee_id

    post BASE, params: { work_order: { title: "Mío" } }, headers: @headers, as: :json
    assert_response :forbidden

    patch "#{BASE}/#{@mine.id}/items/#{work_order_items(:pro_open_labor).id}", params: { unit_price: 1 }, headers: @headers, as: :json
    assert_response :forbidden
    delete "#{BASE}/#{@mine.id}/items/#{work_order_items(:pro_open_labor).id}", headers: @headers
    assert_response :forbidden
  end

  test "staff adds catalog material at the catalog price and never a free price" do
    product = products(:one)
    product.update_columns(company_id: @company.id, price: 75)

    post "#{BASE}/#{@mine.id}/items", params: { product_id: product.id, quantity: 3, unit_price: 1 }, headers: @headers, as: :json
    assert_response :created
    item = response.parsed_body["items"].find { |i| i["product"]&.dig("id") == product.id && i["quantity"].to_f == 3.0 }
    assert_equal 75.0, item["unit_price"].to_f

    post "#{BASE}/#{@mine.id}/items", params: { description: "Libre", unit_price: 10 }, headers: @headers, as: :json
    assert_response :unprocessable_entity
  end

  test "staff cannot add material in order mode" do
    @company.update!(order_mode: :order)
    post "#{BASE}/#{@mine.id}/items", params: { product_id: products(:one).id }, headers: @headers, as: :json
    assert_response :forbidden
  end

  test "allowed_actions for staff never include boss actions" do
    get "#{BASE}/#{@mine.id}", headers: @headers
    actions = response.parsed_body["allowed_actions"]
    assert_includes actions, "start"
    assert_includes actions, "check_steps"
    assert_empty actions & %w[cancel void_charge edit delete edit_items edit_steps]
  end

  test "staff only sees the tickets of their own orders" do
    mine = work_orders(:pro_paid)
    mine.update_columns(employee_id: employees(:pro_staff_employee).id)

    get "/api/v1/tickets", headers: @headers
    assert_response :ok
    assert_equal [ tickets(:pro_paid_ticket).id ], response.parsed_body["results"].map { |t| t["id"] }
  end
end
