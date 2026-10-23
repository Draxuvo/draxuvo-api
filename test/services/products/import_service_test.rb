require "test_helper"

class Products::ImportServiceTest < ActiveSupport::TestCase
  HEADER = "sku,name,description,category,price,unit_cost,stock,min_stock,available".freeze

  def import(csv, company: companies(:one), ext: ".csv", filename: nil)
    Tempfile.create([ "productos", ext ]) do |file|
      file.write(csv)
      file.flush
      upload = filename ? Struct.new(:path, :original_filename).new(file.path, filename) : file
      Products::ImportService.new(company, upload).call
    end
  end

  def csv(*rows) = ([ HEADER ] + rows).join("\n")

  test "creates products from a CSV" do
    result = import(csv("TOR-001,Tornillo,Tornillo de 1 pulgada,Ferretería,$12.50,5.25,100,20,true"))
    assert_equal 1, result.created
    assert_equal 0, result.updated
    assert_empty result.errors
    product = companies(:one).products.find_by!(sku: "TOR-001")
    assert_equal "Tornillo", product.name
    assert_equal "Ferretería", product.category
    assert_equal BigDecimal("12.50"), product.price
    assert_equal BigDecimal("5.25"), product.unit_cost
    assert_equal 100, product.stock
    assert_equal 20, product.min_stock
    assert product.available
  end

  test "updates an existing product by SKU instead of duplicating it" do
    product = products(:one)
    result = import(csv("#{product.sku},Contacto triple,,Eléctrico,99,50,30,5,yes"))
    assert_equal 0, result.created
    assert_equal 1, result.updated
    product.reload
    assert_equal "Contacto triple", product.name
    assert_equal 30, product.stock
    assert_equal BigDecimal("99"), product.price
    assert_equal 1, companies(:one).products.where(sku: product.sku).count
  end

  test "an update without name or stock keeps the current ones" do
    product = products(:one)
    import(csv("#{product.sku},,,,,,,,"))
    product.reload
    assert_equal "Contacto doble", product.name
    assert_equal 18, product.stock
  end

  test "a new product without stock starts at zero" do
    import(csv("NEW-1,Nuevo,,,,,,,"))
    assert_equal 0, companies(:one).products.find_by!(sku: "NEW-1").stock
  end

  test "rows without SKU are reported and skipped" do
    result = import(csv(",Sin sku,,,,,,,", "OK-1,Con sku,,,,,1,,"))
    assert_equal 1, result.created
    assert_equal [ { row: 2, error: I18n.t("products.import.sku_required") } ], result.errors
  end

  test "blank rows are ignored" do
    result = import(csv(",,,,,,,,", "OK-2,Con sku,,,,,1,,"))
    assert_equal 1, result.created
    assert_empty result.errors
  end

  test "rows that fail validation are reported with their SKU" do
    result = import(csv("BAD-1,,,,,,,,"))
    assert_equal 0, result.created
    assert_equal 1, result.errors.size
    assert_equal "BAD-1", result.errors.first[:sku]
    assert_equal 2, result.errors.first[:row]
  end

  test "the available column accepts true, 1, yes, si and defaults to true when empty" do
    import(csv("A-1,A,,,,,,,true", "A-2,B,,,,,,,1", "A-3,C,,,,,,,si", "A-4,D,,,,,,,no", "A-5,E,,,,,,,false", "A-6,F,,,,,,,"))
    rows = companies(:one).products.where(sku: %w[A-1 A-2 A-3 A-4 A-5 A-6]).order(:sku).includes(:product_type)
    # Sin columna de tipo (spec 016): "no disponible" se clasifica como el tipo que no se vende, que queda disponible.
    assert_equal %w[sold sold sold supply supply sold], rows.map { |p| p.product_type.kind }
    assert(rows.all?(&:available))
  end

  test "the type and unit columns pick the company type by name and the unit by key or name" do
    file = Tempfile.new([ "productos", ".csv" ])
    file.write("sku,name,stock,min_stock,product_type,unit\nT-1,Cable,2.5,1,material,Kilogramo\nT-2,Foco,3,,Refacción,pza\n")
    file.close
    result = Products::ImportService.new(companies(:one), Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "productos.csv")).call

    assert_empty result.errors
    cable = companies(:one).products.find_by!(sku: "T-1")
    assert_equal "Material", cable.product_type.name
    assert_equal "kg", cable.unit_key
    assert_equal BigDecimal("2.5"), cable.stock
    assert_equal "Refacción", companies(:one).products.find_by!(sku: "T-2").product_type.name
  end

  test "prices drop currency symbols and thousands separators" do
    import(csv('P-1,Caro,,,"$1,234.50",,,,'))
    assert_equal BigDecimal("1234.50"), companies(:one).products.find_by!(sku: "P-1").price
  end

  test "headers are case and space insensitive" do
    import("SKU,Name,Unit Cost,Min Stock\nH-1,Cabecera,3,2")
    product = companies(:one).products.find_by!(sku: "H-1")
    assert_equal BigDecimal("3"), product.unit_cost
    assert_equal 2, product.min_stock
  end

  test "products are created in the given company only" do
    import(csv("ONLY-1,Solo aquí,,,,,1,,"), company: companies(:two))
    assert companies(:two).products.exists?(sku: "ONLY-1")
    assert_not companies(:one).products.exists?(sku: "ONLY-1")
  end

  test "rejects an unsupported extension" do
    error = assert_raises(ApiErrors::BadRequestError) { import("x", ext: ".txt") }
    assert_equal I18n.t("products.import.unsupported_format"), error.message
  end

  test "the original filename decides the format for uploads" do
    assert_raises(ApiErrors::BadRequestError) { import(csv("Z-1,Z,,,,,,,"), filename: "datos.pdf") }
    assert_equal 1, import(csv("Z-1,Z,,,,,,,"), filename: "datos.CSV").created
  end

  test "generate_template returns a real xlsx workbook with the headers and a sample row" do
    bytes = Products::ImportService.generate_template
    assert bytes.start_with?("PK")
    Tempfile.create([ "plantilla", ".xlsx" ]) do |file|
      file.binmode
      file.write(bytes)
      file.flush
      sheet = Roo::Excelx.new(file.path).sheet(0)
      assert_equal I18n.t("products.import.headers.sku"), sheet.row(1).first
      assert_equal I18n.t("products.import.sample.sku"), sheet.row(2).first
      assert_equal Products::ImportService::HEADER_KEYS.size, sheet.row(1).compact.size
    end
  end

  test "imports a real xlsx workbook" do
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Productos") do |sheet|
      sheet.add_row Products::ImportService::HEADER_KEYS
      sheet.add_row [ "XL-1", "Hoja de cálculo", nil, "General", 10.5, 4, 7, 2, "true" ]
    end
    Tempfile.create([ "productos", ".xlsx" ]) do |file|
      file.binmode
      file.write(package.to_stream.read)
      file.flush
      result = Products::ImportService.new(companies(:one), file).call
      assert_equal 1, result.created
      assert_equal 7, companies(:one).products.find_by!(sku: "XL-1").stock
    end
  end

  test "the downloaded template can be imported back with its localized headers and skips the note row" do
    Tempfile.create([ "plantilla", ".xlsx" ]) do |file|
      file.binmode
      file.write(Products::ImportService.generate_template)
      file.flush
      result = Products::ImportService.new(companies(:one), file).call
      assert_equal 1, result.created
      assert_empty result.errors
      product = companies(:one).products.find_by(sku: I18n.t("products.import.sample.sku"))
      assert_equal I18n.t("products.import.sample.name"), product.name
    end
  end

  test "header labels in English and Spanish map to the same attributes, ignoring accents and case" do
    lookup = Products::ImportService.header_lookup
    assert_equal "unit_cost", lookup["costo_unitario"]
    assert_equal "min_stock", lookup["stock_minimo"]
    assert_equal "category", lookup["categoria"]
    assert_equal "unit_cost", lookup["unit_cost"]
  end

  test "the icon column is applied for admins, ignored for others and for invalid keys" do
    csv = "sku,name,icon\nI-1,Taco,taco\nI-2,Raro,nope\nI-3,Tubo,Pipe\n"
    run = lambda do |allow|
      Tempfile.create([ "productos", ".csv" ]) do |file|
        file.write(csv)
        file.flush
        Products::ImportService.new(companies(:one), file, allow_icon: allow).call
      end
    end

    run.call(false)
    assert_equal [ nil, nil, nil ], companies(:one).products.where(sku: %w[I-1 I-2 I-3]).order(:sku).map(&:icon)

    result = run.call(true)
    assert_empty result.errors
    assert_equal [ "taco", nil, "pipe" ], companies(:one).products.where(sku: %w[I-1 I-2 I-3]).order(:sku).map(&:icon)
  end

  # --- spec 034: códigos de barras, movimientos de stock y resumen ---

  def run_csv(csv, company: companies(:resto_co), user: users(:resto_owner), **options)
    Tempfile.create([ "productos", ".csv" ]) do |file|
      file.write(csv)
      file.flush
      Products::ImportService.new(company, file, user: user, **options).call
    end
  end

  test "reads several barcodes per cell as exact text and adds them to an existing product" do
    result = run_csv("sku,name,barcodes\nBC-1,Cuaderno,\"0012345; 7500000000011\"\nTAC-001,,7500000000028\n")

    assert_empty result.errors
    assert_equal [ "0012345", "7500000000011" ], companies(:resto_co).products.find_by!(sku: "BC-1").barcode_codes
    assert_equal [ "7502000000002", "7500000000028" ], products(:resto_tacos).reload.barcode_codes
  end

  test "a numeric xlsx cell keeps every digit of the barcode" do
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Productos") do |sheet|
      sheet.add_row %w[sku name barcodes]
      sheet.add_row [ "XL-9", "Hoja", 7_501_234_567_890 ]
    end
    Tempfile.create([ "productos", ".xlsx" ]) do |file|
      file.binmode
      file.write(package.to_stream.read)
      file.flush
      Products::ImportService.new(companies(:resto_co), file, user: users(:resto_owner)).call
    end

    assert_equal [ "7501234567890" ], companies(:resto_co).products.find_by!(sku: "XL-9").barcode_codes
  end

  test "a code that belongs to another product or repeats in the file is an error of that row only" do
    result = run_csv("sku,name,barcodes\nNEW-A,Uno,7502000000002\nNEW-B,Dos,8800000000001\nNEW-C,Tres,8800000000001\n")

    assert_equal 1, result.created
    assert_equal [ 2, 4 ], result.errors.map { |e| e[:row] }
    assert_match(/Tacos al pastor/, result.errors.first[:error])
    assert_match(/Dos/, result.errors.last[:error])
    assert_not companies(:resto_co).products.exists?(sku: "NEW-A")
    assert companies(:resto_co).products.exists?(sku: "NEW-B")
    assert_equal [ "7502000000002" ], products(:resto_tacos).reload.barcode_codes
  end

  test "stock changes leave a movement with the user and note, and equal stock leaves none" do
    tacos = products(:resto_tacos)
    assert_difference -> { StockMovement.count }, 2 do
      result = run_csv("sku,name,stock,product_type\nNEW-S,Nuevo con stock,8,Bebida\n#{tacos.sku},,#{tacos.stock + 4},\n")
      assert_equal [ 1, 1, 0 ], [ result.created, result.updated, result.unchanged ]
    end

    entry = StockMovement.joins(:product).find_by!(products: { sku: "NEW-S" })
    assert_equal [ "entry", 8 ], [ entry.movement_type, entry.qty.to_i ]
    adjustment = tacos.stock_movements.order(:id).last
    assert_equal [ "adjustment", 4, users(:resto_owner).id, I18n.t("products.import.stock_note") ], [ adjustment.movement_type, adjustment.qty.to_i, adjustment.user_id, adjustment.note ]
    assert_equal 8, companies(:resto_co).products.find_by!(sku: "NEW-S").stock
  end

  test "importing the same file twice changes nothing the second time" do
    csv = "sku,name,price,stock,barcodes\nR-1,Repetido,10,5,9100000000001\nR-2,Repetido dos,20,7,9100000000018\n"
    first = run_csv(csv)
    assert_equal 2, first.created

    assert_no_difference -> { StockMovement.count } do
      assert_no_difference -> { ProductBarcode.count } do
        second = run_csv(csv)
        assert_equal [ 0, 0, 2 ], [ second.created, second.updated, second.unchanged ]
      end
    end
  end

  test "stock of products that are not counted is ignored and fractions are rejected in whole types" do
    result = run_csv("sku,name,stock,product_type\nSV-1,Servicio,5,Platillo\nFR-1,Fraccion,2.5,Bebida\n")

    assert_equal 1, result.created
    assert_equal [ 3 ], result.errors.map { |e| e[:row] }
    assert_equal 0, companies(:resto_co).products.find_by!(sku: "SV-1").stock
  end

  test "reports progress after each batch" do
    rows = (1..7).map { |i| "P#{i},Producto #{i}" }
    seen = []
    run_csv("sku,name\n#{rows.join("\n")}\n", on_progress: ->(result) { seen << result.processed }, batch_size: 3)

    assert_equal [ 3, 6, 7 ], seen
  end

  test "count_rows counts only data rows" do
    Tempfile.create([ "productos", ".csv" ]) do |file|
      file.write("sku,name\nA,Uno\n,\n# nota\nB,Dos\n")
      file.flush
      assert_equal 2, Products::ImportService.count_rows(file)
    end
  end
end
