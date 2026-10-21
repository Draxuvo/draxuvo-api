require "test_helper"

# Contrato: specs/028-reportes-rediseno/contracts/reports-api.md
class Api::V1::ReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:pro_co)
    @owner = users(:pro_co_owner)
    @headers = auth_headers(@owner, @company)
  end

  def paid_ticket(total, paid_at)
    order = WorkOrder.create!(company: @company, created_by: @owner, title: "Orden", total: total)
    Ticket.create!(work_order: order, company: @company, total: total, status: :paid, payment_method: :cash,
                   amount_received: total, charged_by: @owner, paid_at: paid_at)
  end

  test "summary with from and to uses that range and reports it as custom" do
    paid_ticket(300, Time.zone.local(2026, 3, 12, 12))
    paid_ticket(111, Time.zone.local(2026, 5, 12, 12))

    get "/api/v1/reports/summary", params: { from: "2026-03-01", to: "2026-03-31" }, headers: @headers

    assert_response :ok
    body = response.parsed_body
    assert_equal "custom", body["period"]["type"]
    assert_equal 300.0, body["income"]["total_revenue"]
    assert_not body.key?("previous")
  end

  test "summary with period and date keeps working and from/to win over it" do
    paid_ticket(300, Time.zone.local(2026, 3, 12, 12))

    get "/api/v1/reports/summary", params: { period: "monthly", date: "2026-03-20" }, headers: @headers
    assert_equal "monthly", response.parsed_body["period"]["type"]
    assert_equal 300.0, response.parsed_body["income"]["total_revenue"]

    get "/api/v1/reports/summary", params: { period: "monthly", date: "2026-03-20", from: "2026-04-01", to: "2026-04-30" },
                                    headers: @headers
    assert_equal "custom", response.parsed_body["period"]["type"]
    assert_equal 0.0, response.parsed_body["income"]["total_revenue"]
  end

  test "compare=true adds the previous block with the same length" do
    paid_ticket(200, Time.zone.local(2026, 2, 5, 12))

    get "/api/v1/reports/summary", params: { from: "2026-03-01", to: "2026-03-31", compare: "true" }, headers: @headers

    previous = response.parsed_body["previous"]
    assert_equal "2026-01-29", previous["period"]["from"].first(10)
    assert_equal "2026-02-28", previous["period"]["to"].first(10)
    assert_equal 200.0, previous["income"]["total_revenue"]
    assert previous["expenses"].key?("total")
  end

  test "income accepts group_by day and falls back to month on an unknown value" do
    paid_ticket(100, Time.zone.local(2026, 3, 10, 12))

    get "/api/v1/reports/income", params: { from: "2026-03-01", to: "2026-03-31", group_by: "day" }, headers: @headers
    assert_equal [ "2026-03-10" ], response.parsed_body["by_period"].map { |g| g["period"] }

    get "/api/v1/reports/income", params: { from: "2026-03-01", to: "2026-03-31", group_by: "decade" }, headers: @headers
    assert_equal [ "2026-03" ], response.parsed_body["by_period"].map { |g| g["period"] }
  end

  test "expenses accepts group_by day" do
    get "/api/v1/reports/expenses", params: { from: "2026-03-01", to: "2026-03-31", group_by: "day" }, headers: @headers

    assert_response :ok
  end

  test "a manager gets 403 on every report" do
    manager = create_member(@company, role: :manager)

    %w[summary income expenses payroll].each do |report|
      get "/api/v1/reports/#{report}", headers: auth_headers(manager, @company)

      assert_response :forbidden, "#{report} should be admin only"
    end
  end

  test "reports are scoped to the active company" do
    other = Company.create!(name: "Otra empresa")
    other_owner = create_member(other, role: :owner)
    order = WorkOrder.create!(company: other, created_by: other_owner, title: "Ajena", total: 999)
    Ticket.create!(work_order: order, company: other, total: 999, status: :paid, payment_method: :cash,
                   amount_received: 999, charged_by: other_owner, paid_at: Time.zone.local(2026, 3, 10, 12))

    get "/api/v1/reports/summary", params: { from: "2026-03-01", to: "2026-03-31" }, headers: @headers

    assert_equal 0.0, response.parsed_body["income"]["total_revenue"]
  end
end
