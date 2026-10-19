require "test_helper"

class DiningTableTest < ActiveSupport::TestCase
  test "a table is occupied while it has an open check" do
    assert dining_tables(:table_1).occupied?
    assert_not dining_tables(:table_2).occupied?, "su cuenta está cerrada"
    assert_not dining_tables(:table_3).occupied?
  end

  test "names are unique per company" do
    assert_not companies(:resto_co).dining_tables.build(name: "1").valid?
    assert companies(:pro_co).dining_tables.build(name: "1").valid?
  end
end
