require "test_helper"

class LabelFormatTest < ActiveSupport::TestCase
  def build(over = {})
    companies(:one).label_formats.new({
      name: "Nuevo", kind: "sheet", page_width_mm: 210, page_height_mm: 297, columns: 3, rows: 8, label_width_mm: 63.5,
      label_height_mm: 33.9, margin_top_mm: 13, margin_left_mm: 7.2, gap_x_mm: 2.5, gap_y_mm: 0
    }.merge(over))
  end

  test "a valid sheet and a valid roll" do
    assert build.valid?
    assert build(kind: "roll", page_width_mm: 50, page_height_mm: 30, columns: 1, rows: 1, label_width_mm: 50, label_height_mm: 30,
                 margin_top_mm: 0, margin_left_mm: 0, gap_x_mm: 0, gap_y_mm: 0).valid?
  end

  test "the name is required, trimmed, at most 60 characters and unique per company ignoring case" do
    assert_not build(name: " ").valid?
    assert_not build(name: "x" * 61).valid?
    assert_not build(name: "mis ETIQUETAS 3x8").valid?
    assert companies(:two).label_formats.new(build.attributes.except("id", "company_id").merge("name" => "Mis etiquetas 3x8")).valid?
    assert_equal "Ajustado", build(name: "  Ajustado ").tap(&:valid?).name
  end

  test "dimensions must be positive and within limits" do
    [ { page_width_mm: 0 }, { page_height_mm: -1 }, { page_width_mm: 501 }, { label_width_mm: 9 }, { label_height_mm: 9.99 },
      { margin_top_mm: -0.1 }, { gap_x_mm: -1 }, { columns: 0 }, { rows: 21 }, { columns: 1.5 } ].each do |over|
      assert_not build(over).valid?, "debería rechazar #{over}"
    end
  end

  test "the whole grid must fit the page, horizontally and vertically" do
    wide = build(columns: 4)
    assert_not wide.valid?
    assert wide.errors.of_kind?(:base, :grid_too_wide)

    tall = build(rows: 9)
    assert_not tall.valid?
    assert tall.errors.of_kind?(:base, :grid_too_tall)

    assert build(columns: 3, gap_x_mm: 0.0, margin_left_mm: 0, label_width_mm: 70).valid?
    assert_not build(columns: 3, gap_x_mm: 0.0, margin_left_mm: 0, label_width_mm: 70.01).valid?
  end

  test "a roll has exactly one label" do
    roll = build(kind: "roll", columns: 2, rows: 1, page_width_mm: 100, label_width_mm: 50)
    assert_not roll.valid?
    assert roll.errors.of_kind?(:columns, :roll_single)
  end

  test "a company has at most 20 custom formats" do
    company = companies(:two)
    19.times do |i|
      company.label_formats.create!(name: "F#{i}", kind: "roll", page_width_mm: 50, page_height_mm: 30, columns: 1, rows: 1,
                                    label_width_mm: 50, label_height_mm: 30)
    end
    assert_equal 20, company.label_formats.count
    extra = company.label_formats.new(name: "Uno más", kind: "roll", page_width_mm: 50, page_height_mm: 30, columns: 1, rows: 1,
                                      label_width_mm: 50, label_height_mm: 30)
    assert_not extra.valid?
    assert extra.errors.of_kind?(:base, :formats_limit)
  end

  test "labels per page and the serializer shape" do
    format = label_formats(:one_sheet)
    assert_equal 24, format.labels_per_page
    json = LabelFormatSerializer.new(format).as_json
    assert_equal [ format.id, true, "sheet", 63.5, 33.9, 24, false ], json.values_at(:id, :custom, :kind, :label_width_mm, :label_height_mm, :labels_per_page, :small)
    assert_equal 13, json[:margin_top_mm]
    assert_equal 0, json[:gap_y_mm]
  end
end
