require "test_helper"

class Products::BarcodesTest < ActiveSupport::TestCase
  test "normalizes numeric cells and text without losing digits" do
    assert_equal "7501234567890", Products::Barcodes.normalize(7_501_234_567_890)
    assert_equal "7501234567890", Products::Barcodes.normalize(7_501_234_567_890.0)
    assert_equal "0012345", Products::Barcodes.normalize(" 0012345 ")
    assert_equal "12.5", Products::Barcodes.normalize(12.5)
    assert_nil Products::Barcodes.normalize("  ")
    assert_nil Products::Barcodes.normalize(nil)
  end

  test "splits a cell by semicolon, comma or line break" do
    assert_equal %w[111 222 333], Products::Barcodes.split("111; 222,333\n")
    assert_equal [ "7501234567890" ], Products::Barcodes.split(7_501_234_567_890)
    assert_equal [], Products::Barcodes.split(nil)
  end

  test "clean_list drops blanks and repeats, keeping order" do
    assert_equal %w[a b c], Products::Barcodes.clean_list([ "a", " ", "b", "a", nil, "c" ])
  end

  test "conflicts lists codes owned by another product of the company only" do
    company = companies(:one)
    other = company.products.create!(name: "Otro", sku: "OTR-1", product_type: product_types(:one_sold))

    found = Products::Barcodes.conflicts(company, [ "7501000000001", "9999" ], other)
    assert_equal [ [ "7501000000001", products(:one) ] ], found
    assert_empty Products::Barcodes.conflicts(company, [ "7501000000001" ], products(:one))
    assert_empty Products::Barcodes.conflicts(companies(:two), [ "7501000000001" ])
  end
end
