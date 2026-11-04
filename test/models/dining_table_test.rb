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

  # Spec 054 (H-47): el nombre tiene tope de 100 y solo se exige cuando cambia.
  test "name has a maximum length of 100 that accepts the limit and rejects one more" do
    assert DiningTable.new(company: companies(:resto_co), name: "x" * 100).valid?
    record = DiningTable.new(company: companies(:resto_co), name: "x" * 101)
    assert_not record.valid?
    assert_includes record.errors.attribute_names, :name
  end

  test "an old record with a longer name can still be updated without touching the name" do
    record = DiningTable.new(company: companies(:resto_co), name: "Corto")
    record.save!
    record.update_columns(name: "y" * 300)
    assert record.reload.update(position: 3) if record.respond_to?(:position=)
    assert_not record.update(name: "z" * 300)
  end
end
