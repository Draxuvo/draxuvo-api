require "test_helper"

# Spec 059: tarjetas QR en hoja carta, 4 por hoja.
class Restaurant::MenuCardsPdfTest < ActiveSupport::TestCase
  include LabelPdfHelpers

  setup do
    @company = companies(:resto_co)
    @tables = @company.dining_tables.ordered.to_a.each(&:ensure_menu_token!)
  end

  def render_pdf(tables = @tables) = Restaurant::MenuCardsPdf.new(company: @company, tables: tables).call

  test "letter pages with four cards each" do
    @company.dining_tables.create!(name: "Terraza", position: 9).ensure_menu_token!
    pages = read_pdf(render_pdf(@company.dining_tables.ordered.to_a))

    assert_equal 2, pages.size, "5 mesas → 2 hojas"
    pages.each do |page|
      assert_in_delta 612, page.width, 0.5
      assert_in_delta 792, page.height, 0.5
    end
    assert pages.first.rects.size > 4 * 20, "cada tarjeta dibuja su QR"
  end

  test "each card has the business, the table and the help text, without Draxuvo branding" do
    bytes = render_pdf
    text = pdf_text(bytes)

    assert_equal 4, text.scan("Restaurante Prueba").size
    (1..4).each { |n| assert_includes text, "Mesa #{n}" }
    assert_equal 4, text.scan("Escanea para ver el menú").size
    assert_not_includes bytes, "Draxuvo"
    assert_not_includes text, "Draxuvo"
  end

  test "the help text follows the request language" do
    text = I18n.with_locale(:en) { pdf_text(render_pdf) }
    assert_includes text, "Scan to see the menu"
    assert_includes text, "Table 1"
  end

  test "names keep accents and turn emojis into question marks; non numeric names stay as they are" do
    @company.update!(name: "Café Ñandú 🌮")
    table = @tables.first
    table.update!(name: "Terraza")

    text = pdf_text(render_pdf([ table ]))
    assert_includes text, "Café Ñandú ?"
    assert_includes text, "Terraza"
    assert_not_includes text, "Mesa Terraza"
  end

  test "the QR encodes the menu url of each table" do
    encoded = []
    original = RQRCodeCore::QRCode.method(:new)
    RQRCodeCore::QRCode.stub(:new, ->(text, **opts) { encoded << text; original.call(text, **opts) }) do
      render_pdf
    end
    assert_equal @tables.map(&:menu_url), encoded
  end

  test "tables without a link are refused" do
    table = @company.dining_tables.create!(name: "Nueva")
    assert_raises(ArgumentError) { Restaurant::MenuCardsPdf.new(company: @company, tables: [ table ]) }
  end
end
