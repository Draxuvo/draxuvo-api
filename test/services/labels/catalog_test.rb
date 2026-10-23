require "test_helper"

class Labels::CatalogTest < ActiveSupport::TestCase
  test "every common format fits its page" do
    Labels::Catalog.all.each do |f|
      used_x = f.margin_left_mm + (f.columns * f.label_width_mm) + ((f.columns - 1) * f.gap_x_mm)
      used_y = f.margin_top_mm + (f.rows * f.label_height_mm) + ((f.rows - 1) * f.gap_y_mm)
      assert_operator used_x, :<=, f.page_width_mm + 0.01, "#{f.key} no cabe a lo ancho"
      assert_operator used_y, :<=, f.page_height_mm + 0.01, "#{f.key} no cabe a lo alto"
    end
  end

  test "ids are std: keys and are unique, found by id" do
    ids = Labels::Catalog.all.map(&:id)
    assert_equal ids.uniq, ids
    assert(ids.all? { |id| id.start_with?("std:") })
    assert_equal "a4-65", Labels::Catalog.find("std:a4-65").key
    assert_nil Labels::Catalog.find("std:no-existe")
    assert_nil Labels::Catalog.find("12")
  end

  test "labels per page and kind" do
    a4 = Labels::Catalog.find("std:a4-65")
    assert_equal 65, a4.labels_per_page
    assert_equal "sheet", a4.kind
    assert_equal "roll", Labels::Catalog.find("std:roll-40x30").kind
    assert_equal 1, Labels::Catalog.find("std:roll-40x30").labels_per_page
    assert_not a4.custom?
  end

  test "the name is translated and carries the size" do
    assert_equal "Hoja A4 · 65 etiquetas · 38.1 × 21.2 mm", Labels::Catalog.find("std:a4-65").name
    assert_equal "Rollo · 40 × 30 mm", Labels::Catalog.find("std:roll-40x30").name
    I18n.with_locale(:en) { assert_equal "A4 sheet · 65 labels · 38.1 × 21.2 mm", Labels::Catalog.find("std:a4-65").name }
  end

  test "small is true for the small labels and false for the big ones" do
    small = ->(key) { LabelFormatSerializer.small?(Labels::Catalog.find("std:#{key}")) }
    assert small.call("a4-65")
    assert small.call("roll-30x20")
    assert small.call("letter-80")
    assert_not small.call("a4-10")
    assert_not small.call("roll-60x40")
    assert_not small.call("a4-24")
  end
end
