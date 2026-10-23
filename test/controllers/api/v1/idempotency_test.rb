require "test_helper"
require "stringio"

# Contrato: specs/011-app-movil-hibrida/contracts/api-y-app.md ("Idempotency-Key").
class Api::V1::IdempotencyTest < ActionDispatch::IntegrationTest
  BASE = "/api/v1/work_orders".freeze
  PNG_BYTES = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")

  setup do
    @company = companies(:pro_co)
    @staff = users(:pro_staff)
    @order = work_orders(:pro_open)
    @headers = auth_headers(@staff, @company)
  end

  def note(headers, text: "Falta el cable", order: @order)
    post "#{BASE}/#{order.id}/notes", params: { text: text }, headers: headers, as: :json
  end

  def notes_count(order = @order)
    order.work_order_events.where(kind: :note).count
  end

  test "first request runs and is stored" do
    assert_difference -> { notes_count }, 1 do
      note(@headers.merge("Idempotency-Key" => "k-1"))
    end
    assert_response :created
    assert_equal 1, IdempotencyKey.where(user: @staff, key: "k-1").count
  end

  test "repeated request answers the stored response without a second note" do
    note(@headers.merge("Idempotency-Key" => "k-2"))
    first_body = response.body

    assert_no_difference -> { notes_count } do
      note(@headers.merge("Idempotency-Key" => "k-2"))
    end
    assert_response :created
    assert_equal first_body, response.body
  end

  test "repeated photo upload does not attach a second photo" do
    upload = -> { Rack::Test::UploadedFile.new(StringIO.new(PNG_BYTES), "image/png", original_filename: "f.png") }
    headers = @headers.merge("Idempotency-Key" => "k-photo")

    assert_difference -> { @order.work_order_attachments.count }, 1 do
      post "#{BASE}/#{@order.id}/photos", params: { file: upload.call }, headers: headers
      assert_response :created
      post "#{BASE}/#{@order.id}/photos", params: { file: upload.call }, headers: headers
      assert_response :created
    end
  end

  test "same key on another route is 422 and does nothing" do
    note(@headers.merge("Idempotency-Key" => "k-3"))

    assert_no_difference -> { notes_count(work_orders(:pro_started)) } do
      note(@headers.merge("Idempotency-Key" => "k-3"), order: work_orders(:pro_started))
    end
    assert_response :unprocessable_entity
  end

  test "without the header every request runs as before" do
    assert_difference -> { notes_count }, 2 do
      2.times { note(@headers) }
    end
    assert_equal 0, IdempotencyKey.count
  end

  test "another user can reuse the same key" do
    other = create_member(@company, role: :staff)
    employee = @company.employees.find_by!(user: other)

    note(@headers.merge("Idempotency-Key" => "k-4"))
    @order.update_columns(employee_id: employee.id)
    note(auth_headers(other, @company).merge("Idempotency-Key" => "k-4"))

    assert_equal 2, IdempotencyKey.where(key: "k-4").count
  end

  test "a failed request is not stored, so the retry runs" do
    note(@headers.merge("Idempotency-Key" => "k-5"), order: work_orders(:pro_done))
    assert_response :not_found
    assert_equal 0, IdempotencyKey.where(key: "k-5").count
  end

  test "a key longer than 64 characters is rejected" do
    assert_no_difference -> { notes_count } do
      note(@headers.merge("Idempotency-Key" => "x" * 65))
    end
    assert_response :bad_request
  end
end
