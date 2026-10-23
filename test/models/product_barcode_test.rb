require "test_helper"

class ProductBarcodeTest < ActiveSupport::TestCase
  test "is unique per company but not across companies" do
    dup = ProductBarcode.new(company: companies(:one), product: products(:one), code: "7501000000001")
    assert_not dup.valid?

    other_company = ProductBarcode.new(company: companies(:two), product: products(:two), code: "7501000000001")
    assert other_company.valid?
  end

  test "strips the code, requires it and limits it to 64 characters" do
    barcode = ProductBarcode.new(company: companies(:one), product: products(:one), code: "  ABC-1  ")
    assert barcode.valid?
    assert_equal "ABC-1", barcode.code

    assert_not ProductBarcode.new(company: companies(:one), product: products(:one), code: " ").valid?
    assert_not ProductBarcode.new(company: companies(:one), product: products(:one), code: "9" * 65).valid?
  end

  test "the product must belong to the company" do
    assert_not ProductBarcode.new(company: companies(:one), product: products(:two), code: "ZZZ").valid?
  end

  test "destroying a product removes its codes" do
    assert_difference -> { ProductBarcode.count }, -2 do
      products(:one).destroy!
    end
  end
end
