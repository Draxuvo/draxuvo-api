require "test_helper"

# Contrato: specs/007-ordenes-simples/contracts/api.md ("PATCH /company/order_mode").
class Api::V1::CompanyOrderModeTest < ActionDispatch::IntegrationTest
  PATH = "/api/v1/company/order_mode".freeze

  setup do
    @company = companies(:pro_co)
    @owner = users(:pro_co_owner)
  end

  test "the owner changes the mode and gets the company back" do
    patch PATH, params: { order_mode: "order" }, headers: auth_headers(@owner, @company), as: :json

    assert_response :ok
    assert_equal "order", json["order_mode"]
    assert_equal @company.id, json["id"]
    assert @company.reload.order_mode_order?

    patch PATH, params: { order_mode: "service" }, headers: auth_headers(@owner, @company), as: :json
    assert_response :ok
    assert @company.reload.order_mode_service?
  end

  test "admin, manager and staff get 403 and the mode does not change" do
    %w[admin manager staff].each do |role|
      member = create_member(@company, role: role.to_sym)
      patch PATH, params: { order_mode: "order" }, headers: auth_headers(member, @company), as: :json
      assert_response :forbidden, role
    end
    assert @company.reload.order_mode_service?
  end

  test "an invalid or missing value gets 422" do
    [ "banana", "", nil ].each do |value|
      patch PATH, params: { order_mode: value }, headers: auth_headers(@owner, @company), as: :json
      assert_response :unprocessable_entity, value.inspect
      assert_equal I18n.t("company.invalid_order_mode"), json.dig("error", "message")
    end
    assert @company.reload.order_mode_service?
  end

  test "order_mode appears in user.companies on login and me" do
    @company.update!(order_mode: :order)

    post "/api/v1/auth/login", params: { email: @owner.email, password: "password123" }, as: :json
    assert_response :ok
    listed = json.dig("user", "companies").find { |c| c["id"] == @company.id }
    assert_equal "order", listed["order_mode"]

    get "/api/v1/auth/me", headers: auth_headers(@owner, @company)
    assert_response :ok
    body = json["user"] || json
    assert_equal "order", body["companies"].find { |c| c["id"] == @company.id }["order_mode"]
  end

  test "a new branch inherits the order_mode of its main company" do
    main = companies(:enterprise_co)
    main.update!(order_mode: :order)

    post "/api/v1/company/branches", params: { branch: { name: "Sucursal Modo" } },
         headers: auth_headers(users(:enterprise_co_owner), main), as: :json

    assert_response :created
    assert_equal "order", json.dig("company", "id").then { |id| Company.find(id).order_mode }
  end

  private

  def json
    JSON.parse(response.body)
  end
end
