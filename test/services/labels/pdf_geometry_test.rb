require "test_helper"
require_relative "../../support/label_pdf_helpers"

# SC-003 y SC-004 (spec 035): tamaño de página exacto, cada etiqueta en su cuadro y barras idénticas a la codificación.
class Labels::PdfGeometryTest < ActiveSupport::TestCase
  include LabelPdfHelpers

  setup do
    @company = companies(:resto_co)
    @tacos = products(:resto_tacos)
    @sopa = products(:resto_sopa)
    @sopa.barcodes.create!(company: @company, code: "2900000000018")
  end

  def build(format_id, items, **options)
    format = Labels::Catalog.find(format_id) || label_formats(:one_sheet)
    Labels::PdfService.new(company: @company, format: format, items: items, **options)
  end

  test "the page is exactly the size of the paper" do
    { "std:a4-65" => [ 595.28, 841.89 ], "std:letter-30" => [ 612.0, 792.0 ], "std:roll-40x30" => [ 113.39, 85.04 ] }.each do |id, (w, h)|
      pages = read_pdf(build(id, [ { product_id: @tacos.id, copies: 1 } ]).call)
      assert_equal 1, pages.size
      assert_in_delta w, pages.first.width, 0.02, id
      assert_in_delta h, pages.first.height, 0.02, id
    end
  end

  test "every bar of every label falls inside its cell, within half a millimetre" do
    format = Labels::Catalog.find("std:a4-24")
    layout = Labels::Layout.new(format)
    pages = read_pdf(build("std:a4-24", [ { product_id: @tacos.id, copies: 24 } ]).call)

    assert_equal 1, pages.size
    slots = (0...24).map { |i| layout.slot(i) }
    tolerance = 0.5 * Labels::Layout::MM_TO_PT
    pages.first.rects.each do |x, y, w, h|
      cell = slots.find { |s| x >= s.x - tolerance && x + w <= s.x + s.width + tolerance && y >= s.y - tolerance && y + h <= s.y + s.height + tolerance }
      assert cell, "la barra #{[ x, y, w, h ]} no cae dentro de ninguna etiqueta"
    end
    cells_with_bars = slots.count { |s| pages.first.rects.any? { |x, y, *| x >= s.x && x <= s.x + s.width && y >= s.y && y <= s.y + s.height } }
    assert_equal 24, cells_with_bars
  end

  test "the bars of a label are exactly the modules of the code" do
    pages = read_pdf(build("std:a4-65", [ { product_id: @sopa.id, copies: 1 } ]).call)
    drawing = Labels::BarcodeDrawing.for("2900000000018")
    rects = pages.first.rects.sort_by(&:first)

    runs = drawing.modules.each_with_index.chunk_while { |(a, _), (b, _)| a == b }.select { |run| run.first.first }
    expected_widths = runs.map(&:size)
    expected_offsets = runs.map { |run| run.first.last - runs.first.first.last }
    unit = rects.map { |_x, _y, w, _h| w }.min

    assert_equal expected_widths, rects.map { |_x, _y, w, _h| (w / unit).round }, "los anchos no son los de la codificación"
    assert_equal expected_offsets, rects.map { |x, *| ((x - rects.first.first) / unit).round }, "las posiciones no son las de la codificación"
    assert_in_delta 0.31 * Labels::Layout::MM_TO_PT, unit, 0.01
  end

  def cells_with_bars(page, layout)
    slots = (0...layout.per_page).map { |i| layout.slot(i) }
    slots.count { |s| page.rects.any? { |x, y, *| x >= s.x && x <= s.x + s.width && y >= s.y && y <= s.y + s.height } }
  end

  test "copies, order and the second page" do
    layout = Labels::Layout.new(Labels::Catalog.find("std:a4-65"))
    items = [ { product_id: @tacos.id, copies: 40 }, { product_id: @sopa.id, copies: 30 } ]
    service = build("std:a4-65", items)
    pages = read_pdf(service.call)

    assert_equal 2, pages.size
    assert_equal({ labels_count: 70, pages: 2 }, service.check.slice(:labels_count, :pages))
    assert_equal [ 65, 5 ], pages.map { |page| cells_with_bars(page, layout) }
  end

  test "start_position leaves the first labels of the sheet free" do
    layout = Labels::Layout.new(Labels::Catalog.find("std:a4-65"))
    pages = read_pdf(build("std:a4-65", [ { product_id: @tacos.id, copies: 1 } ], start_position: 7).call)
    first = layout.slot(0, start_position: 7)

    assert_equal [ 1, 1 ], [ first.row, first.column ]
    assert(pages.first.rects.all? { |x, y, *| x >= first.x - 0.5 && y >= first.y - 0.5 })
    assert pages.first.rects.any? { |x, y, *| x >= first.x && y >= first.y && y <= first.y + first.height }
    assert(pages.first.rects.none? { |_x, y, *| y > first.y + first.height + 0.5 }, "no debe haber barras en la fila superior")
  end

  test "a roll makes one page per label" do
    pages = read_pdf(build("std:roll-40x30", [ { product_id: @tacos.id, copies: 3 } ]).call)

    assert_equal 3, pages.size
    assert(pages.all? { |p| p.rects.any? })
  end

  test "a custom format is honored" do
    pages = read_pdf(build("custom", [ { product_id: @tacos.id, copies: 2 } ]).call)

    assert_equal [ 595.28, 841.89 ], [ pages.first.width.round(2), pages.first.height.round(2) ]
  end
end
