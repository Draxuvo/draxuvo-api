require "test_helper"

class Api::V1::SalesCatalogTest < ActionDispatch::IntegrationTest
  def get_catalog(params = {}, user = users(:pos_staff))
    get "/api/v1/sales/catalog", params: params, headers: auth_headers(user, companies(:pos_co))
    response.parsed_body
  end

  test "lists only active, priced products of a type that is sold" do
    skus = get_catalog["results"].map { |p| p["sku"] }.sort
    assert_equal %w[PAP-001 PAP-002 PAP-005 SER-001], skus
  end

  test "does not leak products of other companies" do
    assert_not_includes get_catalog["results"].map { |p| p["sku"] }, "CON-001"
  end

  test "each product carries what the till needs" do
    cuaderno = get_catalog["results"].find { |p| p["sku"] == "PAP-001" }
    assert_equal({ "id" => products(:pos_cuaderno).id, "name" => "Cuaderno profesional", "price" => "42.50", "stock" => 18,
                   "fractional" => false, "barcodes" => [ "7509990000011" ] }, cuaderno.slice("id", "name", "price", "stock", "fractional", "barcodes"))
    assert_equal true, get_catalog["results"].find { |p| p["sku"] == "PAP-005" }["fractional"]
    assert_nil get_catalog["results"].find { |p| p["sku"] == "SER-001" }["stock"]
  end

  test "searches by name, sku and barcode" do
    assert_equal %w[PAP-002], get_catalog(search: "pluma")["results"].map { |p| p["sku"] }
    assert_equal %w[PAP-005], get_catalog(search: "PAP-005")["results"].map { |p| p["sku"] }
    assert_equal %w[PAP-001], get_catalog(search: "7509990000011")["results"].map { |p| p["sku"] }
  end

  test "the exact sku or barcode match goes first" do
    products(:pos_pluma).update!(name: "PAP-001 compatible")
    assert_equal %w[PAP-001 PAP-002], get_catalog(search: "PAP-001")["results"].map { |p| p["sku"] }.first(2)
  end

  test "is paginated" do
    body = get_catalog(page_size: 2)
    assert_equal 2, body["results"].size
    assert body["info"]
  end

  test "needs the pos module" do
    get "/api/v1/sales/catalog", headers: auth_headers(users(:pro_co_owner), companies(:pro_co))
    assert_response :forbidden
  end
end
