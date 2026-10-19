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
end
