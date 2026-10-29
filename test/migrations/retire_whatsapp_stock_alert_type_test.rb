require "test_helper"
require Rails.root.join("db/migrate/20261030100000_retire_whatsapp_stock_alert_type")

# El aviso de stock bajo deja de ser un tipo de mensaje de WhatsApp (spec 048): su fila se conserva, apagada.
class RetireWhatsappStockAlertTypeTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  def insert(kind, enabled:, notified: false)
    ActiveRecord::Base.connection.execute(
      "INSERT INTO whatsapp_message_types (kind, enabled, template_name, template_language, template_status, problem_notified_at, " \
      "lock_version, created_at, updated_at) " \
      "VALUES ('#{kind}', #{enabled}, 'plantilla', 'es_MX', 'approved', #{notified ? 'NOW()' : 'NULL'}, 0, NOW(), NOW())"
    )
  end

  def row(kind) = ActiveRecord::Base.connection.select_one("SELECT * FROM whatsapp_message_types WHERE kind = '#{kind}'")

  def migrate = ActiveRecord::Migration.suppress_messages { RetireWhatsappStockAlertType.new.up }

  test "the stock_alert row is turned off and loses its pending warning, but is kept with its template" do
    insert("stock_alert", enabled: true, notified: true)

    migrate

    stock = row("stock_alert")
    assert_equal false, stock["enabled"]
    assert_nil stock["problem_notified_at"]
    assert_equal [ "plantilla", "es_MX", "approved" ], stock.values_at("template_name", "template_language", "template_status")
  end

  test "it does not touch the types that remain, and deletes nothing" do
    insert("verification_code", enabled: true, notified: true)
    insert("ticket", enabled: true)
    insert("stock_alert", enabled: true)
    before = ActiveRecord::Base.connection.select_value("SELECT count(*) FROM whatsapp_message_types").to_i

    migrate

    assert_equal true, row("verification_code")["enabled"]
    assert_not_nil row("verification_code")["problem_notified_at"]
    assert_equal true, row("ticket")["enabled"]
    assert_equal before, ActiveRecord::Base.connection.select_value("SELECT count(*) FROM whatsapp_message_types").to_i
  end

  test "it is harmless without a stock_alert row and can be run twice" do
    insert("verification_code", enabled: false)

    assert_nothing_raised do
      migrate
      migrate
    end
    assert_nil row("stock_alert")
  end

  test "down does nothing" do
    insert("stock_alert", enabled: false)

    assert_nothing_raised { ActiveRecord::Migration.suppress_messages { RetireWhatsappStockAlertType.new.down } }
    assert_equal false, row("stock_alert")["enabled"]
  end
end
