require "test_helper"

class StationTest < ActiveSupport::TestCase
  setup { @company = companies(:resto_co) }

  test "the first station of a company becomes the default" do
    other = companies(:pro_co)
    first = other.stations.create!(name: "Cocina")
    second = other.stations.create!(name: "Barra")

    assert first.is_default?
    assert_not second.reload.is_default?
  end

  test "making a station the default demotes the previous one" do
    stations(:bar).update!(is_default: true)

    assert stations(:bar).reload.is_default?
    assert_not stations(:kitchen).reload.is_default?
  end

  test "the default station cannot be deactivated" do
    station = stations(:kitchen)

    assert_not station.update(active: false)
    assert_includes station.errors.full_messages.join, I18n.t("restaurant.errors.default_station")
  end

  test "names are unique per company but not across companies" do
    assert_not @company.stations.build(name: "Cocina").valid?
    assert companies(:pro_co).stations.build(name: "Cocina").valid?
  end

  test "default_for falls back to the first active station" do
    stations(:kitchen).update_columns(is_default: false)

    assert_equal stations(:kitchen), Station.default_for(@company)
  end

  # Spec 054 (H-47): el nombre tiene tope de 100 y solo se exige cuando cambia.
  test "name has a maximum length of 100 that accepts the limit and rejects one more" do
    assert Station.new(company: companies(:resto_co), kind: "kitchen", name: "x" * 100).valid?
    record = Station.new(company: companies(:resto_co), kind: "kitchen", name: "x" * 101)
    assert_not record.valid?
    assert_includes record.errors.attribute_names, :name
  end

  test "an old record with a longer name can still be updated without touching the name" do
    record = Station.new(company: companies(:resto_co), kind: "kitchen", name: "Corto")
    record.save!
    record.update_columns(name: "y" * 300)
    assert record.reload.update(position: 3) if record.respond_to?(:position=)
    assert_not record.update(name: "z" * 300)
  end
end
