require "test_helper"

# Spec 059: enlaces públicos del menú de las mesas (contracts/api.md).
class Api::V1::Restaurant::MenuLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:resto_co)
    @owner = users(:resto_owner)
  end

  def headers_for(user) = auth_headers(user, @company)

  test "owner and admin list active tables in floor order and get their links created" do
    dining_tables(:table_3).update!(active: false)
    dining_tables(:table_4).update!(position: 0)
    admin = create_member(@company, role: :admin)

    [ @owner, admin ].each do |user|
      get "/api/v1/restaurant/menu_links", headers: headers_for(user)
      assert_response :ok
      rows = response.parsed_body["results"]
      assert_equal %w[4 1 2], rows.map { |r| r["name"] }
      assert_equal %w[generated_at name table_id url], rows.first.keys.sort
      rows.each { |r| assert_match %r{/m/[A-Za-z0-9_-]{22}\z}, r["url"] }
    end
    assert_nil dining_tables(:table_3).reload.menu_token, "la desactivada no recibe enlace"
    assert_not_nil dining_tables(:table_1).reload.menu_token
  end

  test "listing twice keeps the same links" do
    get "/api/v1/restaurant/menu_links", headers: headers_for(@owner)
    first = response.parsed_body["results"].map { |r| r["url"] }
    get "/api/v1/restaurant/menu_links", headers: headers_for(@owner)
    assert_equal first, response.parsed_body["results"].map { |r| r["url"] }
  end

  test "staff cannot see the links" do
    get "/api/v1/restaurant/menu_links", headers: headers_for(users(:resto_waiter))
    assert_response :forbidden
  end

  test "a company without the restaurant module gets module_not_in_plan" do
    @company.update!(disabled_modules: [ "restaurant" ])
    get "/api/v1/restaurant/menu_links", headers: headers_for(@owner)
    assert_response :forbidden
    assert_equal "module_not_in_plan", response.parsed_body.dig("error", "details", "code")
  end

  # --- US3: regenerar ---

  test "regenerating returns a new link and the old one stops working" do
    table = dining_tables(:table_2)
    old_token = table.ensure_menu_token!

    post "/api/v1/restaurant/tables/#{table.id}/menu_link", headers: headers_for(@owner)
    assert_response :ok
    body = response.parsed_body
    assert_equal table.id, body["table_id"]
    assert_not_includes body["url"], old_token

    get "/api/v1/public/menus/#{old_token}"
    assert_response :not_found
    assert_equal "menu_link_invalid", response.parsed_body.dig("error", "details", "code")
    get "/api/v1/public/menus/#{table.reload.menu_token}"
    assert_response :ok
  end

  test "an inactive table cannot be regenerated" do
    table = dining_tables(:table_2)
    table.update!(active: false)
    post "/api/v1/restaurant/tables/#{table.id}/menu_link", headers: headers_for(@owner)
    assert_response :unprocessable_entity
    assert_equal "table_inactive", response.parsed_body.dig("error", "details", "code")
  end

  test "a table of another company is not found" do
    other = companies(:pro_co).dining_tables.create!(name: "Ajena")
    post "/api/v1/restaurant/tables/#{other.id}/menu_link", headers: headers_for(@owner)
    assert_response :not_found
  end

  test "staff cannot regenerate" do
    post "/api/v1/restaurant/tables/#{dining_tables(:table_1).id}/menu_link", headers: headers_for(users(:resto_waiter))
    assert_response :forbidden
  end
end
