require "test_helper"

# Contrato: specs/037-pago-de-nomina/contracts/payroll-api.md
class Api::V1::PayrollRunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:pro_co)
    @owner = users(:pro_co_owner)
    @admin = create_member(@company, role: :admin, employee: false)
    @manager = users(:pro_manager)
    @staff = users(:pro_staff)
    @ana, @beto = payroll_employees(@company, { name: "Ana", salary: 12_000 }, { name: "Beto", salary: 9_000 })
  end

  def h(user = @owner) = auth_headers(user, @company)

  def create_run(**params)
    post "/api/v1/payroll_runs", params: { period_type: "biweekly", starts_on: "2026-10-01", ends_on: "2026-10-15", **params },
         headers: h, as: :json
  end

  def run_body = response.parsed_body

  # --- permisos ----------------------------------------------------------------------------------

  test "owner and admin can use payroll; manager and staff get 403" do
    [ @owner, @admin ].each do |boss|
      get "/api/v1/payroll_runs", headers: h(boss)
      assert_response :ok
    end
    [ @manager, @staff ].each do |other|
      get "/api/v1/payroll_runs", headers: h(other)
      assert_response :forbidden
      post "/api/v1/payroll_runs", params: { period_type: "monthly", starts_on: "2026-10-01", ends_on: "2026-10-31" }, headers: h(other), as: :json
      assert_response :forbidden
    end
  end

  test "a company without the employees module answers module_not_in_plan" do
    basic = companies(:basic_co)
    basic.update!(disabled_modules: [ "employees" ])
    boss = create_member(basic, role: :owner)

    get "/api/v1/payroll_runs", headers: auth_headers(boss, basic)
    assert_response :forbidden
    assert_equal "module_not_in_plan", response.parsed_body.dig("error", "details", "code")
  end

  test "another company's run answers 404" do
    other_owner = create_member(companies(:one), role: :owner)
    run = build_payroll_run(@company, @owner)

    get "/api/v1/payroll_runs/#{run.id}", headers: auth_headers(other_owner, companies(:one))
    assert_response :not_found
  end

  # --- preparar ----------------------------------------------------------------------------------

  test "creates a draft with a line per active employee and lists it" do
    create_run
    assert_response :created
    assert_equal [ "draft", 1_050_000 ], run_body.values_at("status", "total_cents")
    assert_equal %w[Ana Beto], run_body["payments"].map { |p| p["employee_name"] }
    assert_equal [ "created" ], run_body["events"].map { |e| e["action"] }

    get "/api/v1/payroll_runs", params: { status: "draft", year: 2026 }, headers: h
    assert_equal [ 1 ], [ run_body["results"].size ]
    assert_equal 2, run_body["results"][0]["payments_count"]
  end

  test "an overlapping run answers 409 and a bad period 422" do
    create_run
    create_run(starts_on: "2026-10-10", ends_on: "2026-10-20")
    assert_response :conflict
    assert_equal "period_overlap", run_body.dig("error", "details", "code")

    create_run(starts_on: "2026-11-01", ends_on: "2026-11-30")
    assert_response :unprocessable_entity
    assert_equal "period_invalid", run_body.dig("error", "details", "code")

    create_run(starts_on: "no-date")
    assert_equal "period_invalid", run_body.dig("error", "details", "code")
  end

  test "adjustments recalculate the net and need a note and a positive amount" do
    create_run
    ana = run_body["payments"][0]

    post "/api/v1/payroll_payments/#{ana["id"]}/adjustments", params: { kind: "bonus", amount_cents: 50_000, note: "Puntualidad" }, headers: h, as: :json
    assert_response :created
    post "/api/v1/payroll_payments/#{ana["id"]}/adjustments", params: { kind: "deduction", amount_cents: 20_000, note: "Anticipo" }, headers: h, as: :json
    post "/api/v1/payroll_payments/#{ana["id"]}/adjustments", params: { kind: "bonus", amount_cents: 0, note: "" }, headers: h, as: :json
    assert_response :unprocessable_entity

    get "/api/v1/payroll_runs/#{PayrollRun.last.id}", headers: h
    assert_equal 630_000, run_body["payments"][0]["net_cents"]
    assert_equal 630_000 + 450_000, run_body["total_cents"]
    assert_equal 2, run_body["payments"][0]["adjustments"].size
  end

  test "changing days to pay prorates, and a stale lock_version answers 409" do
    create_run
    id = run_body["id"]
    line = run_body["payments"][0]

    patch "/api/v1/payroll_payments/#{line["id"]}", params: { days_paid: 8, lock_version: run_body["lock_version"] }, headers: h, as: :json
    assert_response :ok
    assert_equal 320_000, run_body["net_cents"]

    patch "/api/v1/payroll_payments/#{line["id"]}", params: { days_paid: 9, lock_version: 0 }, headers: h, as: :json
    assert_response :conflict
    assert_equal "stale_object", run_body.dig("error", "details", "code")

    patch "/api/v1/payroll_payments/#{line["id"]}", params: { days_paid: 99, lock_version: PayrollRun.find(id).lock_version }, headers: h, as: :json
    assert_response :unprocessable_entity
  end

  test "removes a line, refreshes the employees and discards the draft" do
    create_run
    id = run_body["id"]
    beto = run_body["payments"][1]

    delete "/api/v1/payroll_payments/#{beto["id"]}", headers: h
    assert_response :no_content
    @beto.update!(status: :inactive)
    @company.employees.create!(name: "Carla", salary: 6_000, status: :active)

    post "/api/v1/payroll_runs/#{id}/refresh_employees", headers: h
    assert_equal %w[Ana Carla], run_body["payments"].map { |p| p["employee_name"] }.sort

    delete "/api/v1/payroll_runs/#{id}", headers: h
    assert_response :no_content
    assert_not PayrollRun.exists?(id)
  end

  # --- aprobar y pagar ---------------------------------------------------------------------------

  def approve!(id)
    get "/api/v1/payroll_runs/#{id}", headers: h
    post "/api/v1/payroll_runs/#{id}/approve", params: { lock_version: run_body["lock_version"] }, headers: h, as: :json
  end

  test "approve needs the current lock_version and rejects zero nets" do
    create_run
    id = run_body["id"]

    post "/api/v1/payroll_runs/#{id}/approve", params: { lock_version: 99 }, headers: h, as: :json
    assert_response :conflict

    get "/api/v1/payroll_runs/#{id}", headers: h
    ana = run_body["payments"][0]
    post "/api/v1/payroll_payments/#{ana["id"]}/adjustments", params: { kind: "deduction", amount_cents: 700_000, note: "Demasiado" }, headers: h, as: :json
    adjustment = response.parsed_body

    approve!(id)
    assert_response :unprocessable_entity
    assert_equal [ "lines_invalid", [ ana["id"] ] ], [ run_body.dig("error", "details", "code"), run_body.dig("error", "details", "payment_ids") ]

    delete "/api/v1/payroll_adjustments/#{adjustment["id"]}", headers: h
    approve!(id)
    assert_response :ok
    assert_equal "approved", run_body["status"]
  end

  test "pays a line then the rest, with the same Idempotency-Key replaying the answer" do
    create_run
    id = run_body["id"]
    approve!(id)
    ana, beto = run_body["payments"]

    post "/api/v1/payroll_payments/#{ana["id"]}/pay", params: { method: "cash", paid_on: Time.zone.today.to_s }, headers: h, as: :json
    assert_response :ok
    assert_equal [ "paid", "cash" ], response.parsed_body.values_at("status", "method")
    assert_equal "partial", PayrollRun.find(id).status

    keyed = h.merge("Idempotency-Key" => "pagar-resto")
    post "/api/v1/payroll_runs/#{id}/pay_all", params: { method: "transfer", paid_on: Time.zone.today.to_s, reference: "SPEI 9" }, headers: keyed, as: :json
    assert_response :ok
    first = response.body
    assert_no_difference -> { PayrollEvent.count } do
      post "/api/v1/payroll_runs/#{id}/pay_all", params: { method: "transfer", paid_on: Time.zone.today.to_s, reference: "SPEI 9" }, headers: keyed, as: :json
    end
    assert_equal first, response.body
    assert_equal [ "paid", "SPEI 9" ], PayrollRun.find(id).payments.find(beto["id"]).attributes.values_at("status", "reference")
    assert_equal "paid", PayrollRun.find(id).status
  end

  test "paying rejects future dates and an already paid line with other data" do
    create_run
    id = run_body["id"]
    approve!(id)
    ana = run_body["payments"][0]

    post "/api/v1/payroll_payments/#{ana["id"]}/pay", params: { method: "cash", paid_on: 2.days.from_now.to_date.to_s }, headers: h, as: :json
    assert_equal "future_date", response.parsed_body.dig("error", "details", "code")

    post "/api/v1/payroll_payments/#{ana["id"]}/pay", params: { method: "cash", paid_on: Time.zone.today.to_s }, headers: h, as: :json
    post "/api/v1/payroll_payments/#{ana["id"]}/pay", params: { method: "transfer", paid_on: Time.zone.today.to_s }, headers: h, as: :json
    assert_response :unprocessable_entity
    assert_equal "already_paid", response.parsed_body.dig("error", "details", "code")
  end

  test "an approved run no longer accepts changes" do
    create_run
    id = run_body["id"]
    approve!(id)
    line = run_body["payments"][0]

    patch "/api/v1/payroll_payments/#{line["id"]}", params: { days_paid: 5, lock_version: PayrollRun.find(id).lock_version }, headers: h, as: :json
    assert_equal "not_draft", response.parsed_body.dig("error", "details", "code")
    post "/api/v1/payroll_payments/#{line["id"]}/adjustments", params: { kind: "bonus", amount_cents: 1, note: "tarde" }, headers: h, as: :json
    assert_response :unprocessable_entity
    delete "/api/v1/payroll_runs/#{id}", headers: h
    assert_equal "not_draft", response.parsed_body.dig("error", "details", "code")
  end

  test "cancels an approved run with a reason, but not one with payments" do
    create_run
    id = run_body["id"]
    approve!(id)
    ana = run_body["payments"][0]

    post "/api/v1/payroll_runs/#{id}/cancel", params: { reason: "" }, headers: h, as: :json
    assert_equal "reason_required", response.parsed_body.dig("error", "details", "code")

    post "/api/v1/payroll_payments/#{ana["id"]}/pay", params: { method: "cash", paid_on: Time.zone.today.to_s }, headers: h, as: :json
    post "/api/v1/payroll_runs/#{id}/cancel", params: { reason: "Error" }, headers: h, as: :json
    assert_equal "has_payments", response.parsed_body.dig("error", "details", "code")
  end

  # --- recibo, CSV e historial -------------------------------------------------------------------

  test "receipt only for paid lines; export and employee history" do
    create_run
    id = run_body["id"]
    approve!(id)
    ana = run_body["payments"][0]

    get "/api/v1/payroll_payments/#{ana["id"]}", headers: h
    assert_response :unprocessable_entity

    post "/api/v1/payroll_payments/#{ana["id"]}/pay", params: { method: "cash", paid_on: Time.zone.today.to_s, reference: "Caja" }, headers: h, as: :json
    get "/api/v1/payroll_payments/#{ana["id"]}", headers: h
    assert_response :ok
    assert_equal [ "Servicios Pro", "2026-10-01", 600_000 ], [ response.parsed_body.dig("company", "name"), response.parsed_body.dig("run", "starts_on"), response.parsed_body["net_cents"] ]

    get "/api/v1/payroll_runs/#{id}/export", headers: h
    assert_response :ok
    assert_match "text/csv", response.content_type
    assert_includes response.body, "Ana"

    get "/api/v1/employees/#{@ana.id}/payroll_payments", headers: h
    assert_equal [ ana["id"] ], response.parsed_body["results"].map { |p| p["id"] }
    get "/api/v1/employees/#{@ana.id}/payroll_payments", headers: h(@manager)
    assert_response :forbidden
  end

  test "a correction adjustment is accepted for a paid line of the same employee only" do
    create_run
    id = run_body["id"]
    approve!(id)
    ana = run_body["payments"][0]
    post "/api/v1/payroll_payments/#{ana["id"]}/pay", params: { method: "cash", paid_on: Time.zone.today.to_s }, headers: h, as: :json

    create_run(starts_on: "2026-10-16", ends_on: "2026-10-31")
    next_ana, next_beto = run_body["payments"]
    post "/api/v1/payroll_payments/#{next_ana["id"]}/adjustments", params: { kind: "bonus", amount_cents: 1_000, note: "Corrige", corrects_payment_id: ana["id"] }, headers: h, as: :json
    assert_response :created
    assert_equal ana["id"], response.parsed_body["corrects_payment_id"]

    post "/api/v1/payroll_payments/#{next_beto["id"]}/adjustments", params: { kind: "bonus", amount_cents: 1_000, note: "Mal", corrects_payment_id: ana["id"] }, headers: h, as: :json
    assert_response :unprocessable_entity
  end
end
