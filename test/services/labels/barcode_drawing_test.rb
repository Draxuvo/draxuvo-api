require "test_helper"

class Labels::BarcodeDrawingTest < ActiveSupport::TestCase
  test "picks the barcode type from the code as it arrives" do
    assert_equal :ean13, Labels::BarcodeDrawing.for("2900000000018").kind
    assert_equal :ean13, Labels::BarcodeDrawing.for("4006381333931").kind
    assert_equal :ean13, Labels::BarcodeDrawing.for("036000291452").kind
    assert_equal :ean8, Labels::BarcodeDrawing.for("96385074").kind
    assert_equal :code128, Labels::BarcodeDrawing.for("AB-123").kind
    assert_equal :code128, Labels::BarcodeDrawing.for("4006381333932").kind, "13 dígitos con verificador malo van en Code 128"
    assert_equal :code128, Labels::BarcodeDrawing.for("96385075").kind
    assert_equal :code128, Labels::BarcodeDrawing.for("12345").kind
    assert_equal :code128, Labels::BarcodeDrawing.for("036000291453").kind
  end

  test "an EAN-13 has 95 modules and the quiet zones of the standard" do
    drawing = Labels::BarcodeDrawing.for("4006381333931")
    assert_equal 95, drawing.module_count
    assert_equal 18, drawing.quiet_zone_modules
    assert_equal 113, drawing.total_modules
    assert_equal 67, Labels::BarcodeDrawing.for("96385074").module_count
  end

  test "the modules are exactly what Barby encodes" do
    drawing = Labels::BarcodeDrawing.for("2900000000018")
    assert_equal Barby::EAN13.new("290000000001").encoding.chars.map { |bit| bit == "1" }, drawing.modules
    assert_equal "101", Barby::EAN13.new("290000000001").encoding[0, 3]
  end

  test "the module width is the ideal one when there is room and shrinks to fit" do
    drawing = Labels::BarcodeDrawing.for("2900000000018")
    assert_in_delta 0.33, drawing.module_width_mm(60), 1e-9
    assert_in_delta 0.33, drawing.module_width_mm(40), 1e-9
    assert_in_delta 30.0 / 113, drawing.module_width_mm(30), 1e-9
    assert drawing.readable_in?(30)
    assert_not drawing.readable_in?(28)
  end

  test "codes Code 128 cannot encode are unsupported" do
    assert_raises(Labels::BarcodeDrawing::Unsupported) { Labels::BarcodeDrawing.for("niño") }
    assert_raises(Labels::BarcodeDrawing::Unsupported) { Labels::BarcodeDrawing.for("") }
  end

  test "draws the black runs as rectangles within the given width" do
    drawing = Labels::BarcodeDrawing.for("2900000000018")
    pdf = Prawn::Document.new(page_size: [ 200, 100 ], margin: 0)
    drawing.draw(pdf, x: 10, y: 20, width: 150, height: 40)
    content = pdf.render
    rects = content.scan(/^([\d.]+) ([\d.]+) ([\d.]+) ([\d.]+) re$/).map { |r| r.map(&:to_f) }

    assert_operator rects.size, :>, 20
    assert(rects.all? { |x, _y, w, _h| x >= 10 - 0.01 && x + w <= 160 + 0.01 })
    assert(rects.all? { |_x, _y, _w, h| (h - 40).abs < 0.01 })
  end
end
