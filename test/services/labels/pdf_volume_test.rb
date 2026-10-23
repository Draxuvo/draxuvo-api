require "test_helper"

# SC-002 (spec 035): el PDF de 100 etiquetas sale en menos de 10 s y el de 1,000 en menos de 60 s.
class Labels::PdfVolumeTest < ActiveSupport::TestCase
  def build_service(copies, format: "std:a4-65")
    company = companies(:resto_co)
    ids = 10.times.map do |i|
      product = company.products.create!(name: "Producto con nombre largo número #{i}", sku: "ET-#{i}", price: 10 + i, product_type: product_types(:resto_co_sold))
      product.barcodes.create!(company: company, code: Barcodes::Generator.reserve(company, 1).first)
      product.id
    end
    Labels::PdfService.new(company: company, format: Labels::Catalog.find("std:#{format.delete_prefix('std:')}"),
                           items: ids.map { |id| { product_id: id, copies: copies } }, show_name: true, show_price: true)
  end

  test "100 labels in under 10 seconds" do
    service = build_service(10)
    bytes = nil
    elapsed = Benchmark.realtime { bytes = service.call }

    assert_operator elapsed, :<, 10, "100 etiquetas tardaron #{elapsed.round(2)} s"
    assert_equal 2, bytes.scan(%r{/Type /Page$}).size
  end

  test "1,000 labels in under a minute" do
    service = build_service(100, format: "a4-65")
    elapsed = Benchmark.realtime { service.call }

    assert_operator elapsed, :<, 60, "1,000 etiquetas tardaron #{elapsed.round(2)} s"
  end
end
