require "test_helper"

class UnitTest < ActiveSupport::TestCase
  def create_unit(key: "pieza", name: "Pieza", group: "conteo", position: 0)
    Unit.create!(key: key, name: name, group: group, position: position)
  end

  test "key, name and group are required" do
    unit = Unit.new
    assert_not unit.valid?
    %i[key name group].each { |attr| assert unit.errors[attr].any? }
  end

  test "key must be unique" do
    create_unit
    duplicate = Unit.new(key: "pieza", name: "Otra", group: "conteo")
    assert_not duplicate.valid?
    assert duplicate.errors[:key].any?
  end

  test "position defaults to zero" do
    assert_equal 0, Unit.new(key: "x", name: "X", group: "g").position
  end

  test "ordered sorts by group, position and key" do
    c = create_unit(key: "c", group: "b", position: 0)
    b = create_unit(key: "b", group: "a", position: 1)
    a = create_unit(key: "a", group: "a", position: 1)
    first = create_unit(key: "z", group: "a", position: 0)
    assert_equal [ first, a, b, c ], Unit.ordered.where(key: %w[a b c z]).to_a
  end

  test "ensure_catalog! creates the nine units, once, without touching existing ones" do
    Unit.delete_all
    Unit.create!(key: "pza", name: "Pieza editada", group: "conteo", position: 99)

    Unit.ensure_catalog!
    assert_equal %w[g hr kg lt ml mts paq pza serv], Unit.order(:key).pluck(:key)
    edited = Unit.find_by!(key: "pza")
    assert_equal [ "Pieza editada", "conteo", 99 ], [ edited.name, edited.group, edited.position ]

    assert_no_difference -> { Unit.maximum(:updated_at).to_f } do
      Unit.ensure_catalog!
    end
    assert_equal Unit::CATALOG.size, Unit.count
  end

  test "the catalog covers every unit the initial product types point to" do
    keys = Unit::CATALOG.map { |unit| unit[:key] }
    used = ProductTypes::Defaults::DEFINITIONS.values.flatten.map { |definition| definition[:default_unit_key] }
    assert_empty used.uniq - keys
  end
end
