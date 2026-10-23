require "test_helper"

# SC-001 y SC-006 (spec 035): 5,000 códigos sin repetir y 100 productos sin código con su código en pocos segundos.
class Barcodes::GeneratorVolumeTest < ActiveSupport::TestCase
  test "5,000 codes in batches are all different and valid" do
    company = companies(:resto_co)
    codes = 50.times.flat_map { Barcodes::Generator.reserve(company, 100) }

    assert_equal 5_000, codes.uniq.size
    assert(codes.all? { |code| Barcodes::CheckDigit.valid_ean13?(code) })
  end

  test "100 products without a code get one in a single action well under a minute" do
    company = companies(:resto_co)
    type = product_types(:resto_co_sold)
    ids = 100.times.map { |i| company.products.create!(name: "P#{i}", sku: "VOL-#{i}", product_type: type).id }
    products = Product.includes(:barcodes).where(id: ids).to_a

    elapsed = Benchmark.realtime { Barcodes::Generator.assign(company, products) }

    assert_operator elapsed, :<, 5, "asignar 100 códigos tardó #{elapsed.round(2)} s"
    assert_equal 100, ProductBarcode.where(product_id: ids).distinct.count(:code)
  end
end
