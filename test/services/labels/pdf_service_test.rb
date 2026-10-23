require "test_helper"
require_relative "../../support/label_pdf_helpers"

class Labels::PdfServiceTest < ActiveSupport::TestCase
  include LabelPdfHelpers

  setup do
    @company = companies(:resto_co)
    @tacos = products(:resto_tacos) # código 7502000000002, precio 70
    @sopa = products(:resto_sopa)
    @sopa.barcodes.create!(company: @company, code: "2900000000018")
  end

  def service(items, format: "std:a4-65", **options)
    Labels::PdfService.new(company: @company, format: Labels::Catalog.find(format), items: items, **options)
  end

  def text_of(items, **options) = pdf_text(service(items, **options).call)

  test "the name, the number and the price are drawn according to the checkboxes" do
    items = [ { product_id: @tacos.id, copies: 1 } ]

    both = text_of(items, show_name: true, show_price: true)
    assert_includes both, "Tacos al pastor"
    assert_includes both, "7502000000002"
    assert_includes both, "$70.00"

    neither = text_of(items, show_name: false, show_price: false)
    assert_not_includes neither, "Tacos al pastor"
    assert_not_includes neither, "$70.00"
    assert_includes neither, "7502000000002"
  end

  test "a product without a price prints no price at all" do
    @tacos.update_columns(price: nil)

    text = text_of([ { product_id: @tacos.id, copies: 1 } ], show_price: true)

    assert_not_includes text, "$"
  end

  test "the price has two decimals and thousands separators" do
    @tacos.update_columns(price: 1234.5)

    assert_includes text_of([ { product_id: @tacos.id, copies: 1 } ], show_price: true), "$1,234.50"
  end

  test "names with accents and ñ print and what the font cannot hold becomes a question mark" do
    @tacos.update_columns(name: "Piñata áéíóú Ñandú")
    assert_includes text_of([ { product_id: @tacos.id, copies: 1 } ], format: "std:a4-10"), "Piñata áéíóú Ñandú"

    @tacos.update_columns(name: "Café ☃")
    assert_includes text_of([ { product_id: @tacos.id, copies: 1 } ], format: "std:a4-10"), "Café ?"
  end

  test "a long name is cut with ellipsis and never makes the label taller" do
    @tacos.update_columns(name: "Cuaderno profesional universitario de cuadro grande con espiral doble y pasta dura " * 3)
    pages = read_pdf(service([ { product_id: @tacos.id, copies: 1 } ]).call)

    assert_equal 1, pages.size
    assert_includes text_of([ { product_id: @tacos.id, copies: 1 } ]), "..."
    layout = Labels::Layout.new(Labels::Catalog.find("std:a4-65"))
    slot = layout.slot(0)
    assert(pages.first.rects.all? { |_x, y, _w, h| y >= slot.y - 0.5 && y + h <= slot.y + slot.height + 0.5 })
  end

  test "a product from another company is skipped without stopping the rest" do
    result = service([ { product_id: products(:one).id, copies: 2 }, { product_id: @tacos.id, copies: 1 } ]).check

    assert_equal 1, result[:labels_count]
    assert_equal [ { product_id: products(:one).id, reason: "not_found" } ], result[:skipped]
  end

  test "a product without any barcode blocks the PDF and names it" do
    error = assert_raises(Labels::PdfService::Invalid) { service([ { product_id: products(:resto_cola).id, copies: 1 } ]).call }

    assert_equal :no_barcode, error.code
    assert_equal [ { id: products(:resto_cola).id, name: "Refresco de cola" } ], error.details[:products]
  end

  test "an explicit code must belong to the product" do
    ok = service([ { product_id: @sopa.id, copies: 1, code: "2900000000018" } ]).check
    assert_equal 1, ok[:labels_count]

    error = assert_raises(Labels::PdfService::Invalid) { service([ { product_id: @sopa.id, copies: 1, code: "9999" } ]).check }
    assert_equal :invalid_code, error.code
  end

  test "copies, totals and the start position are validated" do
    assert_equal :invalid_copies, assert_raises(Labels::PdfService::Invalid) { service([ { product_id: @tacos.id, copies: 0 } ]).check }.code
    assert_equal :invalid_copies, assert_raises(Labels::PdfService::Invalid) { service([ { product_id: @tacos.id, copies: "x" } ]).check }.code
    assert_equal :empty_items, assert_raises(Labels::PdfService::Invalid) { service([]).check }.code
    assert_equal :invalid_copies, assert_raises(Labels::PdfService::Invalid) { service([ { product_id: @tacos.id, copies: 1001 } ]).check }.code
    assert_equal :too_many_labels, assert_raises(Labels::PdfService::Invalid) { service([ { product_id: @tacos.id, copies: 600 }, { product_id: @sopa.id, copies: 401 } ]).check }.code
    assert_equal 1000, service([ { product_id: @tacos.id, copies: 600 }, { product_id: @sopa.id, copies: 400 } ]).check[:labels_count]
    assert_equal :invalid_start, assert_raises(Labels::PdfService::Invalid) { service([ { product_id: @tacos.id, copies: 1 } ], start_position: 66).check }.code
    assert_equal :invalid_start, assert_raises(Labels::PdfService::Invalid) { service([ { product_id: @tacos.id, copies: 1 } ], start_position: 0).check }.code
  end

  test "a roll ignores nothing but only accepts position 1" do
    assert_equal 1, service([ { product_id: @tacos.id, copies: 1 } ], format: "std:roll-40x30").check[:labels_count]
    assert_equal :invalid_start, assert_raises(Labels::PdfService::Invalid) { service([ { product_id: @tacos.id, copies: 1 } ], format: "std:roll-40x30", start_position: 2).check }.code
  end

  test "warns when the code does not fit readable and when name and price leave too little room for the bars" do
    @tacos.barcodes.destroy_all
    @tacos.barcodes.create!(company: @company, code: "ABCDEFGHIJKLMNOPQRSTUVWXYZ-0123456789")

    long = service([ { product_id: @tacos.id, copies: 3 } ], format: "std:roll-30x20").check
    assert_equal [ [ @tacos.id, "code_too_small" ] ], long[:warnings].map { |w| [ w[:product_id], w[:code] ] }.uniq
    assert_equal I18n.t("labels.warnings.code_too_small"), long[:warnings].first[:message]

    small = service([ { product_id: @sopa.id, copies: 1 } ], format: "std:letter-80", show_name: true, show_price: true).check
    assert_includes small[:warnings].map { |w| w[:code] }, "content_too_big"

    ok = service([ { product_id: @sopa.id, copies: 1 } ], format: "std:a4-24", show_name: true, show_price: true).check
    assert_empty ok[:warnings]
  end

  test "with name and price off the bars of the smallest label are at least six millimetres tall" do
    pages = read_pdf(service([ { product_id: @sopa.id, copies: 1 } ], format: "std:letter-80", show_name: false, show_price: false).call)
    tallest = pages.first.rects.map { |_x, _y, _w, h| h }.max

    assert_operator tallest, :>=, 6.0 * Labels::Layout::MM_TO_PT - 0.5
    assert_empty service([ { product_id: @sopa.id, copies: 1 } ], format: "std:letter-80", show_name: false, show_price: false).check[:warnings]
  end

  test "a code Code 128 cannot encode is skipped and reported" do
    @tacos.barcodes.destroy_all
    ProductBarcode.insert_all!([ { company_id: @company.id, product_id: @tacos.id, code: "niño", created_at: Time.current, updated_at: Time.current } ])

    result = service([ { product_id: @tacos.id, copies: 1 }, { product_id: @sopa.id, copies: 1 } ]).check

    assert_equal 1, result[:labels_count]
    assert_equal [ { product_id: @tacos.id, reason: "code_unsupported" } ], result[:skipped]
  end

  test "a code that is not an EAN is printed as Code 128 exactly as it is" do
    @tacos.barcodes.destroy_all
    @tacos.barcodes.create!(company: @company, code: "AB-123")

    assert_includes text_of([ { product_id: @tacos.id, copies: 1 } ]), "AB-123"
  end
end
