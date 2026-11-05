require "test_helper"

# Spec 057 (US3): crear o reasignar una orden encola el aviso al nuevo responsable.
class Api::V1::WorkOrdersPushTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @company = companies(:pro_co)
    @owner = users(:pro_co_owner)
    @headers = auth_headers(@owner, @company)
  end

  test "creating an order with an assignee enqueues the notice" do
    employee = employees(:pro_staff_employee)

    assert_enqueued_jobs 1, only: Push::WorkOrderAssignedJob do
      post "/api/v1/work_orders", params: { work_order: { title: "Revisar tablero", employee_id: employee.id } }, headers: @headers, as: :json
    end
    assert_response :created
    assert_equal [ response.parsed_body["id"], employee.id, @owner.id ], enqueued_jobs.last[:args]
  end

  test "creating an unassigned order enqueues nothing" do
    assert_no_enqueued_jobs(only: Push::WorkOrderAssignedJob) do
      post "/api/v1/work_orders", params: { work_order: { title: "Sin responsable" } }, headers: @headers, as: :json
    end
  end

  test "reassigning enqueues for the new assignee; editing another field or removing the assignee does not" do
    order = work_orders(:pro_done).tap { |o| o.update_columns(status: WorkOrder.statuses[:open]) }

    assert_enqueued_with(job: Push::WorkOrderAssignedJob, args: [ order.id, employees(:pro_staff_employee).id, @owner.id ]) do
      patch "/api/v1/work_orders/#{order.id}", params: { work_order: { employee_id: employees(:pro_staff_employee).id } }, headers: @headers, as: :json
    end
    assert_response :ok

    assert_no_enqueued_jobs(only: Push::WorkOrderAssignedJob) do
      patch "/api/v1/work_orders/#{order.id}", params: { work_order: { title: "Otro título" } }, headers: @headers, as: :json
      patch "/api/v1/work_orders/#{order.id}", params: { work_order: { employee_id: "" } }, headers: @headers, as: :json
    end
  end
end
