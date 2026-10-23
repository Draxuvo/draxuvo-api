require "test_helper"

class Products::ExportServiceTest < ActiveSupport::TestCase
  def export(products)
    bytes = Products::ExportService.new(products).call
    Tempfile.create([ "export", ".xlsx" ]) do |file|
      file.binmode
      file.write(bytes)
      file.flush
      yield file
    end
  end

  test "writes the template columns, text codes joined with a semicolon, and counted stock" do
    company = companies(:resto_co)
    products(:resto_tacos).replace_barcodes!([ "0012345678905", "7502000000002" ])

    export(company.products.where(sku: "TAC-001")) do |file|
      sheet = Roo::Excelx.new(file.path).sheet(0)
      headers = sheet.row(1)
      assert_equal Products::ImportService::HEADER_KEYS.map { |k| I18n.t("products.import.headers.#{k}") }, headers
      row = headers.zip(sheet.row(2)).to_h
      assert_equal "TAC-001", row[I18n.t("products.import.headers.sku")]
      assert_equal "7502000000002; 0012345678905", row[I18n.t("products.import.headers.barcodes")]
      assert_equal products(:resto_tacos).stock.to_i, row[I18n.t("products.import.headers.stock")]
    end
  end

  test "the exported file imports back without changing anything" do
    company = companies(:resto_co)
    company.products.each { |p| p.replace_barcodes!([ "9400000#{p.id.to_s.rjust(6, '0')}" ]) }

    export(company.products) do |file|
      assert_no_difference -> { StockMovement.count } do
        assert_no_difference -> { company.products.count } do
          result = Products::ImportService.new(company, file, user: users(:resto_owner), allow_icon: true).call
          assert_empty result.errors
          assert_equal [ 0, 0 ], [ result.created, result.updated ]
          assert_equal company.products.count, result.unchanged
        end
      end
    end
  end
end
