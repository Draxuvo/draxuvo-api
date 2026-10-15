require "test_helper"
require "json"

# La excepcion de brakeman para EOLRails (Rails 8.0.2) no puede quedarse
# despues de su vencimiento: esta prueba falla si la entrada sigue en el archivo.
class BrakemanIgnoreExpiryTest < ActiveSupport::TestCase
  IGNORE_FILE = Rails.root.join("config/brakeman.ignore")
  EXPIRY = Date.new(2026, 11, 7)

  test "la entrada vigente menciona la fecha de vencimiento" do
    entry = eol_rails_entries(load_ignore).first
    assert entry, "se esperaba la entrada EOLRails en config/brakeman.ignore"
    assert_includes entry["note"], EXPIRY.iso8601
  end

  test "la excepcion es valida antes del vencimiento" do
    travel_to Time.zone.local(2026, 11, 6, 12) do
      assert_not expired_entry?(load_ignore)
    end
  end

  test "la excepcion vencida falla si la entrada sigue en el archivo" do
    data = load_ignore
    travel_to Time.zone.local(2026, 11, 7, 12) do
      assert expired_entry?(data)
    end
    travel_to Time.zone.local(2027, 1, 1, 12) do
      assert expired_entry?(data)
    end
  end

  test "sin la entrada pasa sin importar la fecha" do
    travel_to Time.zone.local(2030, 1, 1, 12) do
      assert_not expired_entry?("ignored_warnings" => [])
    end
  end

  test "la excepcion de EOLRails no ha vencido" do
    assert_not expired_entry?(load_ignore),
      "config/brakeman.ignore: la excepcion EOLRails vencio el #{EXPIRY}; sube Rails y quita la entrada"
  end

  private

  def load_ignore
    JSON.parse(File.read(IGNORE_FILE))
  end

  def eol_rails_entries(data)
    data.fetch("ignored_warnings").select { |w| w["check_name"] == "EOLRails" }
  end

  # true si la fecha actual es del vencimiento en adelante y la entrada sigue.
  def expired_entry?(data)
    eol_rails_entries(data).any? && Date.current >= EXPIRY
  end
end
