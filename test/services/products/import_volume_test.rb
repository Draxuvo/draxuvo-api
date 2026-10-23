require "test_helper"

# SC-001 y SC-003 (spec 034): 5,000 filas con códigos terminan con margen y reimportarlas no cambia nada.
class Products::ImportVolumeTest < ActiveSupport::TestCase
  ROWS = 5_000
  LIMIT_SECONDS = 120

  test "5,000 rows with barcodes import within the limit and a second import changes nothing" do
    skip "SKIP_VOLUME definido" if ENV["SKIP_VOLUME"].present?

    company = companies(:one)
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Productos") do |sheet|
      sheet.add_row %w[sku name category price unit_cost stock min_stock barcodes]
      ROWS.times do |i|
        sheet.add_row [ "VOL-#{i}", "Producto #{i}", "Cat#{i % 20}", 10 + i % 50, 5 + i % 20, 1 + i % 100, 5,
                        [ "%013d" % (7_500_000_000_000 + i), "0%012d" % i ].join("; ") ],
                      types: [ :string, :string, :string, nil, nil, nil, nil, :string ]
      end
    end

    Tempfile.create([ "volumen", ".xlsx" ]) do |file|
      file.binmode
      file.write(package.to_stream.read)
      file.flush

      result = nil
      elapsed = Benchmark.realtime { result = Products::ImportService.new(company, file, user: users(:pro_co_owner)).call }
      assert_operator elapsed, :<, LIMIT_SECONDS, "importar #{ROWS} filas tardó #{elapsed.round(1)} s"
      assert_equal [ ROWS, 0 ], [ result.created, result.errors_total ]
      assert_equal "0000000000000", ProductBarcode.where(company_id: company.id).find_by!(code: "0000000000000").code
      assert_equal ROWS * 2, ProductBarcode.where(company_id: company.id, product_id: company.products.where("sku LIKE 'VOL-%'")).count

      assert_no_difference -> { StockMovement.count } do
        again = Products::ImportService.new(company, file, user: users(:pro_co_owner)).call
        assert_equal [ 0, 0, ROWS ], [ again.created, again.updated, again.unchanged ]
      end
    end
  end
end
