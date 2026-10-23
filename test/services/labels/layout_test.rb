require "test_helper"

class Labels::LayoutTest < ActiveSupport::TestCase
  def layout(key) = Labels::Layout.new(Labels::Catalog.find("std:#{key}"))

  test "page sizes are exact in points" do
    a4 = layout("a4-65")
    assert_in_delta 595.28, a4.page_width, 0.01
    assert_in_delta 841.89, a4.page_height, 0.01
    letter = layout("letter-30")
    assert_in_delta 612.0, letter.page_width, 0.01
    assert_in_delta 792.0, letter.page_height, 0.01
    roll = layout("roll-40x30")
    assert_in_delta 113.39, roll.page_width, 0.01
    assert_in_delta 85.04, roll.page_height, 0.01
  end

  test "the first, fifth and sixth labels of an A4 sheet of 65 fall where the grid says" do
    l = layout("a4-65")
    first = l.slot(0)
    assert_equal [ 0, 0, 0 ], [ first.page, first.column, first.row ]
    assert_in_delta Labels::Layout.points(4.7), first.x, 0.01
    assert_in_delta l.page_height - Labels::Layout.points(10.7) - Labels::Layout.points(21.2), first.y, 0.01

    fifth = l.slot(4)
    assert_equal [ 4, 0 ], [ fifth.column, fifth.row ]
    assert_in_delta Labels::Layout.points(4.7 + (4 * (38.1 + 2.5))), fifth.x, 0.01

    sixth = l.slot(5)
    assert_equal [ 0, 1 ], [ sixth.column, sixth.row ]
    assert_in_delta first.x, sixth.x, 0.01
    assert_in_delta first.y - Labels::Layout.points(21.2), sixth.y, 0.01
  end

  test "the 66th label starts the second page" do
    l = layout("a4-65")
    slot = l.slot(65)
    assert_equal [ 1, 0, 0 ], [ slot.page, slot.column, slot.row ]
    assert_in_delta l.slot(0).y, slot.y, 0.01
  end

  test "start_position skips labels on the first sheet" do
    l = layout("a4-65")
    assert_equal [ 0, 2 ], [ l.slot(0, start_position: 3).row, l.slot(0, start_position: 3).column ]
    slot = l.slot(0, start_position: 66)
    assert_equal 1, slot.page
    assert_equal 4, l.slot(0, start_position: 5).column
    assert_equal 1, l.slot(1, start_position: 65).page
  end

  test "pages needed" do
    l = layout("a4-65")
    assert_equal 1, l.pages_for(65)
    assert_equal 2, l.pages_for(66)
    assert_equal 2, l.pages_for(65, start_position: 2)
    assert_equal 1, l.pages_for(10, start_position: 5)
    assert_equal 7, layout("roll-50x25").pages_for(7)
  end

  test "a roll puts every label on its own page at the origin" do
    slot = layout("roll-50x25").slot(3)
    assert_equal [ 3, 0, 0 ], [ slot.page, slot.x, slot.y ]
    assert_in_delta 141.73, slot.width, 0.01
    assert_in_delta 70.87, slot.height, 0.01
  end

  test "every label of every common sheet stays inside the page" do
    Labels::Catalog.all.reject { |f| f.paper == "roll" }.each do |format|
      l = Labels::Layout.new(format)
      (0...l.per_page).each do |index|
        s = l.slot(index)
        assert_operator s.x, :>=, -0.01
        assert_operator s.y, :>=, -0.01
        assert_operator s.x + s.width, :<=, l.page_width + 0.01, "#{format.key} etiqueta #{index} se sale a la derecha"
        assert_operator s.y + s.height, :<=, l.page_height + 0.01, "#{format.key} etiqueta #{index} se sale arriba"
      end
    end
  end
end
