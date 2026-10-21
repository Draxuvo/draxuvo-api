require "test_helper"

# Contrato: specs/004-refactor-web-panel/contracts/api.md (GET /attendances): filtro type,
# from/to como días completos en America/Mexico_City, employee_id vacío ignorado y AttendanceSerializer.
class Api::V1::AttendancesControllerTest < ActionDispatch::IntegrationTest
  MEXICO = ActiveSupport::TimeZone["America/Mexico_City"]

  setup do
    @company = companies(:pro_co)
    @owner = users(:pro_co_owner)
    @luis = @company.employees.create!(name: "Luis Pérez", position: "Técnico", status: :active)
    @ana = @company.employees.create!(name: "Ana Ruiz", position: nil, status: :active)
  end

  test "type filters by attendance_type" do
    record(@luis, MEXICO.local(2026, 10, 14, 8, 0), :normal)
    late = record(@luis, MEXICO.local(2026, 10, 13, 9, 15), :late)
    record(@ana, MEXICO.local(2026, 10, 14, 9, 0), :absent)

    get "/api/v1/attendances", params: { type: "late" }, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal [ late.id ], ids
  end

  test "an invalid type is ignored" do
    record(@luis, MEXICO.local(2026, 10, 14, 8, 0), :normal)
    record(@ana, MEXICO.local(2026, 10, 14, 9, 0), :late)

    get "/api/v1/attendances", params: { type: "foo" }, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal 2, response.parsed_body.dig("info", "total")
  end

  test "from and to are whole inclusive days in Mexico City" do
    record(@luis, MEXICO.local(2026, 10, 13, 23, 30), :normal)                 # 05:30 UTC del 14: día anterior
    first = record(@luis, MEXICO.local(2026, 10, 14, 0, 30), :normal)          # 06:30 UTC del 14
    last = record(@ana, MEXICO.local(2026, 10, 14, 23, 30), :late)             # 05:30 UTC del 15
    record(@ana, MEXICO.local(2026, 10, 15, 0, 30), :normal)                   # día siguiente

    get "/api/v1/attendances", params: { from: "2026-10-14", to: "2026-10-14" }, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal [ first.id, last.id ].sort, ids.sort
  end

  test "from alone and to alone are inclusive" do
    before = record(@luis, MEXICO.local(2026, 10, 13, 12, 0), :normal)
    on_day = record(@luis, MEXICO.local(2026, 10, 14, 23, 30), :normal)
    after = record(@ana, MEXICO.local(2026, 10, 15, 0, 30), :normal)

    get "/api/v1/attendances", params: { from: "2026-10-14" }, headers: auth_headers(@owner, @company)
    assert_response :ok
    assert_equal [ on_day.id, after.id ].sort, ids.sort

    get "/api/v1/attendances", params: { to: "2026-10-14" }, headers: auth_headers(@owner, @company)
    assert_response :ok
    assert_equal [ before.id, on_day.id ].sort, ids.sort
  end

  test "an unreadable date is ignored" do
    record(@luis, MEXICO.local(2026, 10, 14, 8, 0), :normal)
    record(@ana, MEXICO.local(2026, 10, 12, 8, 0), :normal)

    get "/api/v1/attendances", params: { from: "not-a-date", to: "foo" }, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal 2, response.parsed_body.dig("info", "total")
  end

  test "an empty employee_id is ignored and a present one filters" do
    luis_record = record(@luis, MEXICO.local(2026, 10, 14, 8, 0), :normal)
    record(@ana, MEXICO.local(2026, 10, 14, 9, 0), :late)

    get "/api/v1/attendances", params: { employee_id: "" }, headers: auth_headers(@owner, @company)
    assert_response :ok
    assert_equal 2, response.parsed_body.dig("info", "total")

    get "/api/v1/attendances", params: { employee_id: @luis.id }, headers: auth_headers(@owner, @company)
    assert_response :ok
    assert_equal [ luis_record.id ], ids
  end

  test "each result carries the attendance fields and its employee" do
    attendance = @company.attendances.create!(
      employee: @luis, checkin_at: MEXICO.local(2026, 10, 14, 9, 12), attendance_type: :late,
      lat: 19.4326, lng: -99.1332
    )
    record(@ana, MEXICO.local(2026, 10, 13, 8, 0), :normal)

    get "/api/v1/attendances", headers: auth_headers(@owner, @company)

    assert_response :ok
    results = response.parsed_body["results"]
    row = results.find { |r| r["id"] == attendance.id }
    assert_equal %w[attendance_type checkin_at checkout_at company_id created_at duration_minutes employee employee_id id lat lng open updated_at],
                 row.keys.sort
    assert_equal @luis.id, row["employee_id"]
    assert_equal @company.id, row["company_id"]
    assert_equal "late", row["attendance_type"]
    assert_nil row["checkout_at"]
    assert_equal "19.4326", row["lat"]
    assert_equal "-99.1332", row["lng"]
    assert_equal({ "id" => @luis.id, "name" => "Luis Pérez", "position" => "Técnico" }, row["employee"])
    assert_match(/-06:00\z/, row["checkin_at"], "timestamps use the America/Mexico_City offset")

    ana_row = results.find { |r| r["employee_id"] == @ana.id }
    assert_equal({ "id" => @ana.id, "name" => "Ana Ruiz", "position" => nil }, ana_row["employee"])
  end

  test "another company's attendances are not listed" do
    own = record(@luis, MEXICO.local(2026, 10, 14, 8, 0), :late)
    other_company = companies(:enterprise_co)
    other_employee = other_company.employees.create!(name: "Ajeno", status: :active)
    other_company.attendances.create!(employee: other_employee, checkin_at: MEXICO.local(2026, 10, 14, 8, 0), attendance_type: :late)

    get "/api/v1/attendances", params: { type: "late" }, headers: auth_headers(@owner, @company)
    assert_response :ok
    assert_equal [ own.id ], ids

    get "/api/v1/attendances", params: { employee_id: other_employee.id }, headers: auth_headers(@owner, @company)
    assert_response :ok
    assert_equal 0, response.parsed_body.dig("info", "total")
  end

  private

  def record(employee, checkin_at, type)
    @company.attendances.create!(employee: employee, checkin_at: checkin_at, attendance_type: type)
  end

  def ids
    response.parsed_body["results"].map { |r| r["id"] }
  end
end
