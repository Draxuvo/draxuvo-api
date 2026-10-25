require "test_helper"

class Api::V1::Restaurant::TablesControllerTest < ActionDispatch::IntegrationTest
  setup { @company = companies(:resto_co) }

  def get_tables(user, headers: {})
    get "/api/v1/restaurant/tables", headers: auth_headers(user, @company).merge(headers)
  end

  test "lists every table with the open check on the occupied ones" do
    get_tables(users(:resto_waiter))

    assert_response :ok
    tables = response.parsed_body["results"].index_by { |t| t["name"] }
    assert_equal 4, tables.size
    assert_nil tables["3"]["check"]
    check = tables["1"]["check"]
    assert_equal checks(:open_check).id, check["id"]
    assert_equal true, check["mine"]
    assert_equal({ "new" => 1, "preparing" => 1, "ready" => 1, "delivered" => 0 }, check["counts"])
    assert_equal "155.00", check["total"]
  end

  test "another waiter sees the same tables but they are not theirs" do
    get_tables(users(:resto_waiter2))

    check = response.parsed_body["results"].find { |t| t["name"] == "1" }["check"]
    assert_equal false, check["mine"]
  end

  test "takeout checks come apart from the tables" do
    get_tables(users(:resto_waiter2))

    takeouts = response.parsed_body["takeouts"]
    assert_equal [ "Luis" ], takeouts.map { |c| c["takeout_name"] }
    assert_equal true, takeouts.first["mine"]
  end

  test "lists the checks closed today, with total and waiter only for the owner of the check or a boss" do
    Check.where(id: checks(:closed_check).id).update_all(closed_at: Time.current)

    get_tables(users(:resto_waiter))
    closed = response.parsed_body["closed_today"].first
    assert_equal checks(:closed_check).id, closed["id"]
    assert_equal "2", closed["name"]
    assert_equal true, closed["mine"]
    assert_equal "70.00", closed["total"]
    assert_equal users(:resto_waiter).id, closed["waiter"]["id"]

    get_tables(users(:resto_waiter2))
    other = response.parsed_body["closed_today"].first
    assert_equal false, other["mine"]
    assert_not other.key?("total")
    assert_not other.key?("waiter")

    get_tables(users(:resto_owner))
    assert_equal "70.00", response.parsed_body["closed_today"].first["total"]
  end

  test "checks closed on another day or cancelled are not listed as closed today" do
    Check.where(id: checks(:closed_check).id).update_all(closed_at: 2.days.ago)
    Check.where(id: checks(:open_check).id).update_all(status: Check.statuses[:cancelled], closed_at: Time.current)

    get_tables(users(:resto_owner))

    assert_equal [], response.parsed_body["closed_today"]
  end

  test "ready items are only those of the caller's own checks" do
    get_tables(users(:resto_waiter))
    mine = response.parsed_body["ready_items"]
    assert_equal [ "Refresco de cola" ], mine.map { |i| i["name"] }
    assert_equal "1", mine.first["table"]

    get_tables(users(:resto_waiter2))
    assert_empty response.parsed_body["ready_items"]
  end

  test "stock alerts count only for a boss" do
    get_tables(users(:resto_owner))
    assert_equal 1, response.parsed_body["stock_alerts"]

    get_tables(users(:resto_waiter))
    assert_not response.parsed_body.key?("stock_alerts")
  end

  test "answers 304 when nothing changed" do
    get_tables(users(:resto_waiter))
    etag = response.headers["ETag"]
    assert etag.present?

    get_tables(users(:resto_waiter), headers: { "If-None-Match" => etag })
    assert_response :not_modified
  end

  test "the etag changes when an item changes state" do
    get_tables(users(:resto_waiter))
    etag = response.headers["ETag"]

    travel 2.seconds do
      check_items(:item_new).update!(status: :preparing, preparing_at: Time.current)
      get_tables(users(:resto_waiter), headers: { "If-None-Match" => etag })
    end

    assert_response :ok
  end

  test "a company without the restaurant module gets 403" do
    get "/api/v1/restaurant/tables", headers: auth_headers(users(:basic_co_owner), companies(:basic_co))

    assert_response :forbidden
    assert_equal "module_not_in_plan", response.parsed_body.dig("error", "details", "code")
  end

  test "a person from another company cannot use this company" do
    get "/api/v1/restaurant/tables", headers: auth_headers(users(:pro_co_owner)).merge("X-Company-Id" => @company.id.to_s)

    assert_response :forbidden
  end

  test "an expired subscription is blocked" do
    @company.subscription.update!(status: :expired)
    get_tables(users(:resto_waiter))

    assert_response :forbidden
  end

  test "requires a session" do
    get "/api/v1/restaurant/tables"

    assert_response :unauthorized
  end

  test "each table carries its state" do
    get_tables(users(:resto_waiter))
    tables = response.parsed_body["results"].index_by { |t| t["name"] }

    assert_equal "free", tables["3"]["state"]
    assert_equal "occupied", tables["1"]["state"]
  end

  test "a table whose items were all delivered is to pay" do
    settle_check(checks(:open_check))
    get_tables(users(:resto_waiter))

    assert_equal "to_pay", response.parsed_body["results"].find { |t| t["name"] == "1" }["state"]
  end

  test "a waiter does not see total or waiter of other people's checks" do
    get_tables(users(:resto_waiter2))
    check = response.parsed_body["results"].find { |t| t["name"] == "1" }

    assert_equal "occupied", check["state"]
    assert_equal false, check["check"]["mine"]
    assert check["check"]["opened_at"].present?
    assert_not check["check"].key?("total")
    assert_not check["check"].key?("waiter")
  end

  test "a boss sees total and waiter of every check" do
    get_tables(users(:resto_owner))
    check = response.parsed_body["results"].find { |t| t["name"] == "1" }["check"]

    assert_equal "155.00", check["total"]
    assert check["waiter"].present?
  end

  test "the overview is only for a boss" do
    get_tables(users(:resto_owner))
    overview = response.parsed_body["overview"]
    assert_equal 2, overview["open_checks"]
    assert_equal 2, overview["pending_comandas"]

    get_tables(users(:resto_waiter))
    assert_not response.parsed_body.key?("overview")
  end
end
