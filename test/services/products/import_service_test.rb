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
end
