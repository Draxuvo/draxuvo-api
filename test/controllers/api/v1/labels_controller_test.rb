require "test_helper"
require_relative "../../../support/label_pdf_helpers"

class Api::V1::LabelsControllerTest < ActionDispatch::IntegrationTest
  include LabelPdfHelpers

  setup do
    @company = companies(:resto_co)
    @waiter = auth_headers(users(:resto_waiter), @company)
    @owner = auth_headers(users(:resto_owner), @company)
    @tacos = products(:resto_tacos)
  end

  def body(items, **over)
    { format_id: "std:a4-65", show_name: true, show_price: false, start_position: 1, items: items }.merge(over)
  end

  def post_labels(action, items, headers: @waiter, **over)
    post "/api/v1/labels/#{action}", params: body(items, **over), headers: headers, as: :json
  end

  test "pdf answers a PDF with the exact page size, as an attachment" do
    post_labels(:pdf, [ { product_id: @tacos.id, copies: 5 } ])

    assert_response :ok
    assert_equal "application/pdf", response.media_type
    assert_match(/attachment; filename="etiquetas.pdf"/, response.headers["Content-Disposition"])
    page = read_pdf(response.body.b).first
    assert_equal [ 595.28, 841.89 ], [ page.width, page.height ]
    assert_includes pdf_text(response.body.b), "Tacos al pastor"
  end

  test "check answers the summary and warnings without a file" do
    post_labels(:check, [ { product_id: @tacos.id, copies: 70 }, { product_id: 0, copies: 1 } ])

    assert_response :ok
    assert_equal 70, response.parsed_body["labels_count"]
    assert_equal 2, response.parsed_body["pages"]
    assert_equal [ { "product_id" => 0, "reason" => "not_found" } ], response.parsed_body["skipped"]
    assert_equal [], response.parsed_body["warnings"]
  end

  test "an own format of the company can be used, one of another company cannot" do
    own = @company.label_formats.create!(name: "Mía", kind: "roll", page_width_mm: 50, page_height_mm: 30, columns: 1, rows: 1, label_width_mm: 50, label_height_mm: 30)
    post_labels(:pdf, [ { product_id: @tacos.id, copies: 2 } ], format_id: own.id)
    assert_response :ok
    assert_equal 2, read_pdf(response.body.b).size

    post_labels(:pdf, [ { product_id: @tacos.id, copies: 1 } ], format_id: label_formats(:one_sheet).id)
    assert_response :unprocessable_entity
    assert_equal "invalid_format", response.parsed_body.dig("error", "details", "code")

    post_labels(:pdf, [ { product_id: @tacos.id, copies: 1 } ], format_id: "std:no-existe")
    assert_equal "invalid_format", response.parsed_body.dig("error", "details", "code")
  end

  test "a product of another company is left out of the PDF" do
    post_labels(:check, [ { product_id: products(:one).id, copies: 3 }, { product_id: @tacos.id, copies: 1 } ])

    assert_equal 1, response.parsed_body["labels_count"]
    assert_equal [ products(:one).id ], response.parsed_body["skipped"].map { |s| s["product_id"] }
  end

  test "each failure answers 422 with its code" do
    cola = products(:resto_cola)
    cases = {
      "no_barcode" => [ [ { product_id: cola.id, copies: 1 } ], {} ],
      "too_many_labels" => [ [ { product_id: @tacos.id, copies: 600 }, { product_id: cola.id, copies: 401 } ], {} ],
      "invalid_copies" => [ [ { product_id: @tacos.id, copies: 0 } ], {} ],
      "invalid_code" => [ [ { product_id: @tacos.id, copies: 1, code: "000" } ], {} ],
      "invalid_start" => [ [ { product_id: @tacos.id, copies: 1 } ], { start_position: 99 } ],
      "empty_items" => [ [], {} ]
    }
    cases.each do |code, (items, over)|
      post_labels(:pdf, items, **over)
      assert_response :unprocessable_entity, code
      assert_equal code, response.parsed_body.dig("error", "details", "code")
    end
    post_labels(:check, [ { product_id: cola.id, copies: 1 } ])
    assert_equal [ { "id" => cola.id, "name" => "Refresco de cola" } ], response.parsed_body.dig("error", "details", "products")
  end

  test "the name and price checkboxes are honored" do
    post_labels(:pdf, [ { product_id: @tacos.id, copies: 1 } ], show_name: false, show_price: true)

    text = pdf_text(response.body.b)
    assert_not_includes text, "Tacos al pastor"
    assert_includes text, "$70.00"
  end

  test "any member can print and a company without the inventory module cannot" do
    post_labels(:pdf, [ { product_id: @tacos.id, copies: 1 } ], headers: @waiter)
    assert_response :ok

    @company.update!(disabled_modules: [ "inventory" ])
    post_labels(:pdf, [ { product_id: @tacos.id, copies: 1 } ], headers: @owner)
    assert_response :forbidden
    assert_equal "module_not_in_plan", response.parsed_body.dig("error", "details", "code")
  end
end
