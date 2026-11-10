require "test_helper"

# Spec 059: PDF de tarjetas QR (contracts/api.md).
class Api::V1::Restaurant::MenuCardsControllerTest < ActionDispatch::IntegrationTest
  include LabelPdfHelpers

  setup do
    @company = companies(:resto_co)
    @owner = users(:resto_owner)
  end

  def headers_for(user) = auth_headers(user, @company)

  def download(ids = nil, user: @owner)
    params = ids.nil? ? {} : { table_ids: ids }
    post "/api/v1/restaurant/menu_cards/pdf", params: params, headers: headers_for(user), as: :json
  end

  test "without ids prints every active table and creates the missing links" do
    dining_tables(:table_4).update!(active: false)
    download
    assert_response :ok
    assert_equal "application/pdf", response.media_type
    assert_includes response.headers["Content-Disposition"], "tarjetas-qr.pdf"

    text = pdf_text(response.body)
    %w[1 2 3].each { |n| assert_includes text, "Mesa #{n}" }
    assert_not_includes text, "Mesa 4"
    assert_equal 1, read_pdf(response.body).size
    assert @company.dining_tables.active.all? { |t| t.menu_token.present? }
  end

  test "with ids prints only those tables" do
    download([ dining_tables(:table_2).id ])
    assert_response :ok
    text = pdf_text(response.body)
    assert_includes text, "Mesa 2"
    assert_not_includes text, "Mesa 1"
  end

  test "ids of another company or of inactive tables are rejected" do
    dining_tables(:table_3).update!(active: false)
    other = companies(:pro_co).dining_tables.create!(name: "Ajena")

    download([ dining_tables(:table_1).id, dining_tables(:table_3).id, other.id ])
    assert_response :unprocessable_entity
    details = response.parsed_body.dig("error", "details")
    assert_equal "invalid_tables", details["code"]
    assert_equal [ dining_tables(:table_3).id, other.id ].sort, details["table_ids"].sort
  end

  test "without active tables answers no_tables" do
    @company.dining_tables.update_all(active: false)
    download
    assert_response :unprocessable_entity
    assert_equal "no_tables", response.parsed_body.dig("error", "details", "code")
  end

  test "more than the maximum answers too_many_tables" do
    extra = (Api::V1::Restaurant::MenuCardsController::MAX_TABLES - 3).times.map do |n|
      { company_id: @company.id, name: "Extra #{n}", position: 100 + n, active: true }
    end
    DiningTable.insert_all!(extra)
    assert_operator @company.dining_tables.active.count, :>, Api::V1::Restaurant::MenuCardsController::MAX_TABLES

    download
    assert_response :unprocessable_entity
    assert_equal "too_many_tables", response.parsed_body.dig("error", "details", "code")
  end

  test "staff cannot print cards" do
    download(user: users(:resto_waiter))
    assert_response :forbidden
  end

  test "a company without the restaurant module gets module_not_in_plan" do
    @company.update!(disabled_modules: [ "restaurant" ])
    download
    assert_response :forbidden
    assert_equal "module_not_in_plan", response.parsed_body.dig("error", "details", "code")
  end
end
