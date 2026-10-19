require "test_helper"

class Api::V1::Restaurant::StockAlertsControllerTest < ActionDispatch::IntegrationTest
  setup { @company = companies(:resto_co) }

  def alerts(user) = get("/api/v1/restaurant/stock_alerts", headers: auth_headers(user, @company))

  test "a boss sees the tracked products that are low" do
    alerts(users(:resto_manager))

    assert_response :ok
    assert_equal [ [ "Refresco de cola", 2, 3, false ] ],
                 response.parsed_body["results"].map { |a| a.values_at("name", "stock", "min_stock", "sold_out") }
  end

  test "a product appears as sold out when what remains is committed" do
    products(:resto_tacos).update!(stock: 1) # 1 existencia y 1 ya comprometido en la cuenta abierta
    alerts(users(:resto_owner))

    tacos = response.parsed_body["results"].find { |a| a["name"] == "Tacos al pastor" }
    assert_equal true, tacos["sold_out"]
  end

  test "a product that does not track stock never alerts" do
    products(:resto_sopa).update!(stock: 0, min_stock: 5)
    alerts(users(:resto_manager))

    assert_not_includes response.parsed_body["results"].map { |a| a["name"] }, "Sopa del día"
  end

  test "a waiter cannot read the alerts" do
    alerts(users(:resto_waiter))

    assert_response :forbidden
  end

  test "no alerts answers an empty list" do
    products(:resto_cola).update!(stock: 50)
    alerts(users(:resto_manager))

    assert_empty response.parsed_body["results"]
  end
end
