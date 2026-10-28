require "test_helper"

# Contrato: specs/045-alertas-operativas/contracts/api.md (/alert_settings).
class Api::V1::AlertSettingsControllerTest < ActionDispatch::IntegrationTest
  PATH = "/api/v1/alert_settings".freeze

  setup do
    @company = companies(:resto_co)
    @owner = create_member(@company, role: :owner)
    Product.where(company_id: @company.id).update_all(stock: 1000) # que el stock bajo no mezcle las cuentas
  end

  def json = JSON.parse(response.body)

  def patch_settings(body, user: @owner, company: @company)
    patch PATH, params: body, headers: auth_headers(user, company), as: :json
  end

  test "GET returns the effective values, the defaults and the applicable kinds" do
    get PATH, headers: auth_headers(@owner, @company)

    assert_response :ok
    assert_equal 90, json.dig("thresholds", "table_open")
    assert_equal({ "kitchen" => 10, "bar" => 5, "other" => 10 }, json.dig("thresholds", "kitchen_wait"))
    assert_equal json["thresholds"], json["defaults"]
    assert_equal [ 8, "America/Mexico_City" ], [ json["summary_hour"], json["time_zone"] ]
    assert_equal %w[kitchen_wait kitchen_preparing work_order_stalled table_open low_stock].sort, json["applicable"].sort
  end

  test "applicable follows the active modules of the company" do
    @company.update!(disabled_modules: [ "restaurant", "work_orders" ])
    get PATH, headers: auth_headers(@owner, @company)
    assert_equal [ "low_stock" ], json["applicable"]
  end

  test "PATCH changes only what it receives and the new limit applies right away" do
    Check.where(id: checks(:open_check).id).update_all(opened_at: 45.minutes.ago)
    table_alerts = -> { get("/api/v1/alerts", headers: auth_headers(@owner, @company)); JSON.parse(response.body)["results"].count { |alert| alert["kind"] == "table_open" } }
    assert_equal 0, table_alerts.call

    patch_settings({ thresholds: { table_open: 30 }, summary_hour: 9 })
    assert_response :ok
    assert_equal 30, json.dig("thresholds", "table_open")
    assert_equal 9, json["summary_hour"]
    assert_equal 1440, json.dig("thresholds", "work_order_stalled")
    assert_equal 90, json.dig("defaults", "table_open")

    assert_equal 1, table_alerts.call
  end

  test "a station kind can be changed without touching the others" do
    patch_settings({ thresholds: { kitchen_wait: { bar: 2 } } })
    assert_equal({ "kitchen" => 10, "bar" => 2, "other" => 10 }, json.dig("thresholds", "kitchen_wait"))
  end

  test "values out of range or unknown are rejected and nothing is saved" do
    [ { table_open: 0 }, { table_open: 10_081 }, { table_open: -3 }, { table_open: "soon" }, { low_stock: 5 },
      { kitchen_wait: { banquets: 5 } } ].each do |bad|
      patch_settings({ thresholds: bad })
      assert_response :unprocessable_entity, bad.inspect
    end
    patch_settings({ summary_hour: 24 })
    assert_response :unprocessable_entity
    patch_settings({ time_zone: "Mars/Olympus" })
    assert_response :unprocessable_entity
    assert_equal 0, AlertSetting.count
  end

  test "the time zone can be changed" do
    patch_settings({ time_zone: "America/Tijuana" })
    assert_response :ok
    assert_equal "America/Tijuana", json["time_zone"]
  end

  test "staff cannot read or change it, and admins and the super admin can" do
    waiter = create_member(@company, role: :staff)
    get PATH, headers: auth_headers(waiter, @company)
    assert_response :forbidden
    patch_settings({ summary_hour: 7 }, user: waiter)
    assert_response :forbidden

    patch_settings({ summary_hour: 7 }, user: create_member(@company, role: :admin))
    assert_response :ok
    patch_settings({ summary_hour: 6 }, user: users(:super_admin))
    assert_response :ok
  end

  test "each company has its own setting" do
    patch_settings({ thresholds: { table_open: 20 } })
    other_owner = create_member(companies(:pro_co), role: :owner)
    get PATH, headers: auth_headers(other_owner, companies(:pro_co))
    assert_equal 90, json.dig("thresholds", "table_open")
  end
end
