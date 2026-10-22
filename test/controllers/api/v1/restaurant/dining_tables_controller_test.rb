require "test_helper"

class Api::V1::Restaurant::DiningTablesControllerTest < ActionDispatch::IntegrationTest
  setup { @company = companies(:resto_co) }

  def headers_for(user) = auth_headers(user, @company)

  test "a boss creates a table" do
    post "/api/v1/restaurant/tables", params: { table: { name: "Terraza 1" } }, headers: headers_for(users(:resto_manager)), as: :json

    assert_response :created
    assert_equal "Terraza 1", response.parsed_body["name"]
    assert_equal 5, @company.dining_tables.count
  end

  test "a duplicate name answers 422" do
    post "/api/v1/restaurant/tables", params: { name: "1" }, headers: headers_for(users(:resto_owner)), as: :json

    assert_response :unprocessable_entity
  end

  test "a waiter cannot create or edit tables" do
    post "/api/v1/restaurant/tables", params: { name: "9" }, headers: headers_for(users(:resto_waiter)), as: :json
    assert_response :forbidden

    patch "/api/v1/restaurant/tables/#{dining_tables(:table_1).id}", params: { name: "x" }, headers: headers_for(users(:resto_waiter)), as: :json
    assert_response :forbidden
  end

  test "a boss renames and deactivates a table" do
    patch "/api/v1/restaurant/tables/#{dining_tables(:table_4).id}", params: { table: { name: "Barra 4", active: false } },
                                                                     headers: headers_for(users(:resto_manager)), as: :json

    assert_response :ok
    table = dining_tables(:table_4).reload
    assert_equal [ "Barra 4", false ], [ table.name, table.active ]
  end

  test "a table of another company is not found" do
    foreign = companies(:pro_co).dining_tables.create!(name: "X")
    patch "/api/v1/restaurant/tables/#{foreign.id}", params: { name: "y" }, headers: headers_for(users(:resto_owner)), as: :json

    assert_response :not_found
  end

  test "a boss reorders the floor plan by changing a table position, and the list follows it" do
    table = dining_tables(:table_1)
    patch "/api/v1/restaurant/tables/#{table.id}", params: { table: { position: 99 } }, headers: headers_for(users(:resto_manager)), as: :json

    assert_response :ok
    assert_equal 99, response.parsed_body["position"]
    get "/api/v1/restaurant/tables", headers: headers_for(users(:resto_manager))
    assert_equal table.name, response.parsed_body["results"].last["name"]
  end
end
