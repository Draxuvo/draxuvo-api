require "test_helper"

class Api::V1::LabelFormatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:resto_co)
    @waiter = auth_headers(users(:resto_waiter), @company)
    @owner = auth_headers(users(:resto_owner), @company)
  end

  VALID = {
    name: "Mi hoja 3x7", kind: "sheet", page_width_mm: 210, page_height_mm: 297, columns: 3, rows: 7, label_width_mm: 63.5,
    label_height_mm: 38.1, margin_top_mm: 15.1, margin_left_mm: 7.2, gap_x_mm: 2.5, gap_y_mm: 0
  }.freeze

  def create_format(headers: @waiter, **over)
    post "/api/v1/label_formats", params: { label_format: VALID.merge(over) }, headers: headers, as: :json
  end

  test "lists the common formats first and then the company's own" do
    create_format
    get "/api/v1/label_formats", headers: @waiter

    assert_response :ok
    results = response.parsed_body["results"]
    common = results.select { |f| !f["custom"] }
    assert_equal Labels::Catalog.all.size, common.size
    assert(common.all? { |f| f["id"].start_with?("std:") })
    assert_equal results.first(common.size), common
    own = results.last
    assert_equal [ "Mi hoja 3x7", true, "sheet", 21, false ], own.values_at("name", "custom", "kind", "labels_per_page", "small")
    assert_kind_of Integer, own["id"]
  end

  test "any member creates, edits and deletes an own format" do
    create_format
    assert_response :created
    id = response.parsed_body["id"]

    patch "/api/v1/label_formats/#{id}", params: { label_format: { name: "Renombrada", margin_top_mm: 14.5 } }, headers: @owner, as: :json
    assert_response :ok
    assert_equal [ "Renombrada", 14.5 ], response.parsed_body.values_at("name", "margin_top_mm")

    delete "/api/v1/label_formats/#{id}", headers: @waiter
    assert_response :no_content
    assert_not LabelFormat.exists?(id)
  end

  test "impossible measures are rejected with the reason and nothing is saved" do
    assert_no_difference -> { LabelFormat.count } do
      create_format(columns: 4)
    end

    assert_response :unprocessable_entity
    details = response.parsed_body.dig("error", "details")
    assert_equal "invalid_dimensions", details["code"]
    assert details["errors"].key?("base")
    assert_match(/ancho/, response.parsed_body.dig("error", "message"))

    create_format(label_width_mm: 0)
    assert_response :unprocessable_entity
    assert details_keys = response.parsed_body.dig("error", "details", "errors").keys
    assert_includes details_keys, "label_width_mm"
  end

  test "a repeated name answers name_taken and the 21st format answers formats_limit" do
    create_format
    create_format
    assert_response :unprocessable_entity
    assert_equal "name_taken", response.parsed_body.dig("error", "details", "code")

    19.times { |i| create_format(name: "Formato #{i}") }
    assert_equal 20, @company.label_formats.count
    create_format(name: "El veintiuno")
    assert_response :unprocessable_entity
    assert_equal "formats_limit", response.parsed_body.dig("error", "details", "code")
  end

  test "a common format cannot be edited or deleted and another company's format does not exist" do
    patch "/api/v1/label_formats/std:a4-65", params: { label_format: { name: "x" } }, headers: @owner, as: :json
    assert_response :not_found
    delete "/api/v1/label_formats/std:a4-65", headers: @owner
    assert_response :not_found

    other = label_formats(:one_sheet)
    patch "/api/v1/label_formats/#{other.id}", params: { label_format: { name: "x" } }, headers: @owner, as: :json
    assert_response :not_found
    delete "/api/v1/label_formats/#{other.id}", headers: @owner
    assert_response :not_found
    assert LabelFormat.exists?(other.id)

    get "/api/v1/label_formats", headers: @owner
    assert_not_includes response.parsed_body["results"].map { |f| f["name"] }, other.name
  end

  test "a company with the inventory module turned off is refused" do
    @company.update!(disabled_modules: [ "inventory" ])

    get "/api/v1/label_formats", headers: @owner

    assert_response :forbidden
    assert_equal "module_not_in_plan", response.parsed_body.dig("error", "details", "code")
  end
end
