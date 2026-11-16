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

  # Spec 065: con logo (spec 063) cada tarjeta lo muestra arriba; el QR no cambia.
  def attach_logo
    file = Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/logo.png"), "image/png", original_filename: "logo.png")
    @company.attach_logo!(file)
    @company.reload
  end

  def image_count(bytes) = bytes.b.scan("/Subtype /Image").size

  # Rectángulos del QR de la tarjeta de arriba a la izquierda (x < media hoja, y > media hoja).
  def first_qr_bounds(bytes)
    rects = bytes.b.scan(/^(-?[\d.]+) (-?[\d.]+) ([\d.]+) ([\d.]+) re$/).map { |r| r.map(&:to_f) }
                 .select { |x, y, w, h| x < 306 && y > 396 && w < 120 && h < 10 }
    xs = rects.map { |x, _y, w, _h| [ x, x + w ] }.flatten
    ys = rects.map { |_x, y, _w, h| [ y, y + h ] }.flatten
    { width: xs.max - xs.min, height: ys.max - ys.min, top: ys.max }
  end

  test "without a logo the cards have no image (as before)" do
    assert_equal 0, image_count(render_pdf)
  end

  test "with a logo every sheet draws it and keeps the business, the table and the help text" do
    attach_logo
    bytes = render_pdf
    assert_operator image_count(bytes), :>=, 1
    assert_equal 4, bytes.b.scan(/\/I\d+ Do/).size, "el logo se dibuja en las 4 tarjetas"
    text = pdf_text(bytes)
    assert_equal 4, text.scan("Restaurante Prueba").size
    assert_equal 4, text.scan("Escanea para ver el menú").size
  end

  test "if the logo cannot be read the cards are generated without it" do
    attach_logo
    @company.stub(:logo_print_io, -> { raise "R2 caído" }) do
      bytes = render_pdf
      assert bytes.start_with?("%PDF")
      assert_equal 0, image_count(bytes)
    end
  end

  test "with a logo the QR keeps its size and everything fits inside the 10 mm margin" do
    plain = first_qr_bounds(render_pdf)
    attach_logo
    with_logo = first_qr_bounds(render_pdf)
    assert_in_delta plain[:width], with_logo[:width], 0.01
    assert_in_delta plain[:height], with_logo[:height], 0.01

    usable = Restaurant::MenuCardsPdf::CARD_HEIGHT - (2 * Restaurant::MenuCardsPdf::PADDING)
    assert_operator Restaurant::MenuCardsPdf.content_height(logo: true), :<=, usable
    assert_operator Restaurant::MenuCardsPdf.content_height(logo: false), :<=, usable
  end
end
