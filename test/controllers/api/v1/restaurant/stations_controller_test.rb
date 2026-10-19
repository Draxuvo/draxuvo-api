require "test_helper"

class Api::V1::Restaurant::StationsControllerTest < ActionDispatch::IntegrationTest
  setup { @company = companies(:resto_co) }

  def headers_for(user) = auth_headers(user, @company)

  test "any member lists the stations in order" do
    get "/api/v1/restaurant/stations", headers: headers_for(users(:resto_waiter))

    assert_response :ok
    assert_equal %w[Cocina Barra], response.parsed_body["results"].map { |s| s["name"] }
    assert_equal true, response.parsed_body["results"].first["is_default"]
  end

  test "a boss creates a station, accepting the params wrapped or flat" do
    post "/api/v1/restaurant/stations", params: { station: { name: "Parrilla" } }, headers: headers_for(users(:resto_manager)), as: :json
    assert_response :created
    assert_equal "Parrilla", response.parsed_body["name"]

    post "/api/v1/restaurant/stations", params: { name: "Postres" }, headers: headers_for(users(:resto_manager)), as: :json
    assert_response :created
  end

  test "a waiter cannot create or edit stations" do
    post "/api/v1/restaurant/stations", params: { name: "Parrilla" }, headers: headers_for(users(:resto_waiter)), as: :json
    assert_response :forbidden

    patch "/api/v1/restaurant/stations/#{stations(:bar).id}", params: { name: "X" }, headers: headers_for(users(:resto_waiter)), as: :json
    assert_response :forbidden
    assert_equal "Barra", stations(:bar).reload.name
  end

  test "a duplicate name answers 422" do
    post "/api/v1/restaurant/stations", params: { name: "Cocina" }, headers: headers_for(users(:resto_owner)), as: :json

    assert_response :unprocessable_entity
  end

  test "making another station the default demotes the first" do
    patch "/api/v1/restaurant/stations/#{stations(:bar).id}", params: { is_default: true }, headers: headers_for(users(:resto_owner)), as: :json

    assert_response :ok
    assert stations(:bar).reload.is_default?
    assert_not stations(:kitchen).reload.is_default?
  end

  test "the default station cannot be deactivated without picking another" do
    patch "/api/v1/restaurant/stations/#{stations(:kitchen).id}", params: { active: false }, headers: headers_for(users(:resto_owner)), as: :json
    assert_response :unprocessable_entity
    assert stations(:kitchen).reload.active?

    patch "/api/v1/restaurant/stations/#{stations(:bar).id}", params: { is_default: true }, headers: headers_for(users(:resto_owner)), as: :json
    patch "/api/v1/restaurant/stations/#{stations(:kitchen).id}", params: { active: false }, headers: headers_for(users(:resto_owner)), as: :json
    assert_response :ok
  end

  test "a product without a station falls into the default one when sent" do
    assert_nil products(:resto_agua).station
    assert_equal stations(:kitchen), Station.default_for(@company)
  end

  test "a station of another company is not found" do
    foreign = companies(:pro_co).stations.create!(name: "Ajena")
    patch "/api/v1/restaurant/stations/#{foreign.id}", params: { name: "x" }, headers: headers_for(users(:resto_owner)), as: :json

    assert_response :not_found
  end
end
