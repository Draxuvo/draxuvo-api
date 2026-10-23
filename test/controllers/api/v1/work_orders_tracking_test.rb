require "test_helper"

# Contrato: specs/007-ordenes-simples/contracts/api.md (summary, reasignación, historia). FR-014 a FR-016.
class Api::V1::WorkOrdersTrackingTest < ActionDispatch::IntegrationTest
  BASE = "/api/v1/work_orders".freeze

  setup do
    @company = companies(:pro_co)
    @owner = users(:pro_co_owner)
    @manager = users(:pro_manager)
    @staff = users(:pro_staff)
    @boss_headers = auth_headers(@owner, @company)
  end

  test "summary counts the groups and the amount to charge" do
    get "#{BASE}/summary", headers: @boss_headers
    assert_response :ok
    body = response.parsed_body
    assert_equal 2, body.dig("counts", "open")
    assert_equal 1, body.dig("counts", "in_progress")
    assert_equal 1, body.dig("counts", "done")
    assert_equal 1, body.dig("counts", "cancelled")
    assert_equal 1, body.dig("counts", "unassigned")
    assert_equal 850.0, body["to_charge_total"].to_f
  end

  test "summary is limited to the staff member's own orders" do
    get "#{BASE}/summary", headers: auth_headers(@staff, @company)
    assert_response :ok
    assert_equal 0, response.parsed_body.dig("counts", "done")
    assert_equal 1, response.parsed_body.dig("counts", "open")
  end

  test "list filters unassigned and paid_on" do
    get BASE, params: { unassigned: "true" }, headers: @boss_headers
    assert_equal [ work_orders(:pro_unassigned).id ], response.parsed_body["results"].map { |o| o["id"] }

    work_orders(:pro_paid).update_columns(updated_at: Time.current)
    tickets(:pro_paid_ticket).update_columns(paid_at: Time.current)
    get BASE, params: { status: "paid", paid_on: Time.current.in_time_zone("America/Mexico_City").to_date.to_s }, headers: @boss_headers
    assert_equal [ work_orders(:pro_paid).id ], response.parsed_body["results"].map { |o| o["id"] }
  end

  test "reassigning moves the order between staff and writes the event" do
    order = work_orders(:pro_open)
    other_user = create_member(@company, role: :staff, employee: false)
    other_employee = employees(:pro_other_employee)
    other_employee.update!(user: other_user)

    patch "#{BASE}/#{order.id}", params: { work_order: { employee_id: other_employee.id } }, headers: @boss_headers, as: :json
    assert_response :ok
    reassigned = response.parsed_body["events"].find { |e| e["kind"] == "reassigned" }
    assert_equal employees(:pro_staff_employee).name, reassigned.dig("data", "from", "name")
    assert_equal other_employee.name, reassigned.dig("data", "to", "name")

    get "#{BASE}/#{order.id}", headers: auth_headers(@staff, @company)
    assert_response :not_found
    get "#{BASE}/#{order.id}", headers: auth_headers(other_user, @company)
    assert_response :ok
  end

  test "reassigning to nobody leaves the order unassigned" do
    order = work_orders(:pro_open)
    patch "#{BASE}/#{order.id}", params: { work_order: { employee_id: "" } }, headers: @boss_headers, as: :json
    assert_response :ok
    assert_nil response.parsed_body["employee"]
  end

  test "a paid order cannot be edited, reassigned or given new items" do
    order = work_orders(:pro_paid)
    patch "#{BASE}/#{order.id}", params: { work_order: { title: "Otro" } }, headers: @boss_headers, as: :json
    assert_response :unprocessable_entity
    assert_equal "Lámparas de sala", order.reload.title

    post "#{BASE}/#{order.id}/items", params: { description: "Extra", unit_price: 10 }, headers: @boss_headers, as: :json
    assert_response :unprocessable_entity
  end

  test "the history comes in chronological order with the person and the time" do
    order = work_orders(:pro_started)
    get "#{BASE}/#{order.id}", headers: @boss_headers
    events = response.parsed_body["events"]
    assert_equal %w[created started], events.map { |e| e["kind"] }
    assert_equal events.sort_by { |e| e["created_at"] }, events
    assert events.all? { |e| e.dig("actor", "name").present? && e["created_at"].present? }
  end

  test "a charge and a void leave the full trail" do
    order = work_orders(:pro_done)
    post "#{BASE}/#{order.id}/charge", params: { payment_method: "card" }, headers: @boss_headers, as: :json
    assert_response :ok
    post "#{BASE}/#{order.id}/void_charge", params: { reason: "Cobro duplicado" }, headers: @boss_headers, as: :json
    assert_response :ok
    kinds = response.parsed_body["events"].map { |e| e["kind"] }
    assert_equal %w[charged voided], kinds.last(2)
    voided = response.parsed_body["events"].last
    assert_equal "Cobro duplicado", voided.dig("data", "reason")
  end

  test "a manager edits, reassigns and cancels but cannot void a charge or delete" do
    headers = auth_headers(@manager, @company)
    order = work_orders(:pro_open)

    patch "#{BASE}/#{order.id}", params: { work_order: { title: "Editada por gerente" } }, headers: headers, as: :json
    assert_response :ok

    post "#{BASE}/#{order.id}/cancel", params: { reason: "Sin material" }, headers: headers, as: :json
    assert_response :ok
    assert_equal "cancelled", response.parsed_body["status"]

    post "#{BASE}/#{work_orders(:pro_done).id}/charge", params: { payment_method: "card" }, headers: headers, as: :json
    assert_response :ok
    post "#{BASE}/#{work_orders(:pro_done).id}/void_charge", params: { reason: "x" }, headers: headers, as: :json
    assert_response :forbidden

    delete "#{BASE}/#{work_orders(:pro_unassigned).id}", headers: headers
    assert_response :forbidden
  end

  test "allowed_actions for a manager include edit but not delete or void" do
    get "#{BASE}/#{work_orders(:pro_done).id}", headers: auth_headers(@manager, @company)
    actions = response.parsed_body["allowed_actions"]
    assert_includes actions, "edit"
    assert_includes actions, "charge"
    assert_empty actions & %w[delete void_charge]
  end

  test "orders of another company are never visible" do
    get "#{BASE}/#{work_orders(:one_order).id}", headers: @boss_headers
    assert_response :not_found
  end
end
