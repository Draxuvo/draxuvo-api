require "test_helper"

# Spec 059: GET /api/v1/public/menus/:token (contracts/api.md).
class Api::V1::Public::MenusControllerTest < ActionDispatch::IntegrationTest
  setup do
    Api::V1::Public::MenusController::RATE_LIMIT_STORE.clear
    @table = dining_tables(:table_4)
    @token = @table.ensure_menu_token!
  end

  def open_menu(token = @token, headers: {})
    get "/api/v1/public/menus/#{token}", headers: headers
  end

  test "anyone can read the menu without session or company header" do
    open_menu
    assert_response :ok
    body = response.parsed_body
    assert_equal "Restaurante Prueba", body.dig("business", "name")
    assert_equal "4", body.dig("table", "name")
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "the response has exactly the whitelisted keys (SC-004)" do
    products(:resto_sopa).update!(description: "Caldo de pollo", icon: "soup")
    open_menu
    body = response.parsed_body

    assert_equal %w[business categories table], body.keys.sort
    assert_equal %w[name], body["business"].keys
    assert_equal %w[name], body["table"].keys
    body["categories"].each do |category|
      assert_equal %w[items name], category.keys.sort
      category["items"].each do |item|
        assert_equal %w[description icon name price_cents sold_out], item.keys.sort
      end
    end

    raw = response.body
    %w[sku stock unit_cost barcodes product_type station_id available_qty company_id waiter].each do |key|
      assert_not_includes raw, "\"#{key}\"", "no expone #{key}"
    end
  end

  test "prices are integer cents and icons are resolved" do
    products(:resto_sopa).update!(price: 28.5, icon: nil)
    product_types(:resto_co_sold).update!(icon: "soup")
    open_menu

    sopa = response.parsed_body["categories"].flat_map { |c| c["items"] }.find { |i| i["name"] == "Sopa del día" }
    assert_equal 2850, sopa["price_cents"]
    assert_kind_of Integer, sopa["price_cents"]
    assert_equal "soup", sopa["icon"], "sin icono propio usa el de su tipo"
  end

  test "an invalid link answers 404 menu_link_invalid" do
    open_menu("token-que-no-existe-123")
    assert_response :not_found
    assert_equal "menu_link_invalid", response.parsed_body.dig("error", "details", "code")
  end

  test "an unavailable menu answers 403 menu_unavailable without the internal reason" do
    subscriptions(:resto_co).update_columns(status: Subscription.statuses[:suspended])
    open_menu
    assert_response :forbidden
    details = response.parsed_body.dig("error", "details")
    assert_equal({ "code" => "menu_unavailable" }, details)
  end

  test "too many requests from the same IP answer 429" do
    with_env("PUBLIC_MENU_RATE_LIMIT" => "3") do
      3.times { open_menu; assert_response :ok }
      open_menu
      assert_response :too_many_requests
    end
  end

  test "CORS allows only the public site origin" do
    with_env("PUBLIC_SITE_URL" => "http://localhost:4300") do
      open_menu(headers: { "Origin" => "http://localhost:4300" })
      assert_equal "http://localhost:4300", response.headers["Access-Control-Allow-Origin"]

      open_menu(headers: { "Origin" => "https://sitio-ajeno.example" })
      assert_nil response.headers["Access-Control-Allow-Origin"]
    end
  end
end
