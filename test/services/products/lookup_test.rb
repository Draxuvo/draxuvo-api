require "test_helper"

class Products::LookupTest < ActiveSupport::TestCase
  test "finds by barcode, then by sku, exactly" do
    company = companies(:one)
    assert_equal products(:one), Products::Lookup.call(company, "7501000000018")
    assert_equal products(:one), Products::Lookup.call(company, " 7501000000001 ")
    assert_equal products(:one), Products::Lookup.call(company, "CON-001")
    assert_nil Products::Lookup.call(company, "75010000")
    assert_nil Products::Lookup.call(company, "")
  end

  test "never crosses companies" do
    assert_nil Products::Lookup.call(companies(:two), "7501000000001")
    assert_nil Products::Lookup.call(companies(:one), "CIN-001")
  end

  test "a barcode wins over a sku with the same text" do
    company = companies(:one)
    other = company.products.create!(name: "Tiene SKU igual", sku: "7501000000018", product_type: product_types(:one_sold))

    assert_equal products(:one), Products::Lookup.call(company, "7501000000018")
    assert_not_equal other, Products::Lookup.call(company, "7501000000018")
  end
end
