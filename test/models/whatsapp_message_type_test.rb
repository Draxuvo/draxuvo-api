require "test_helper"

class WhatsappMessageTypeTest < ActiveSupport::TestCase
  setup { WhatsappMessageType.ensure_all! }

  def type(kind) = WhatsappMessageType.find_by!(kind: kind)

  def connect!(status: "connected")
    WhatsappConnection.current.update!(access_token: "EAAGsecreto0123456789", phone_number_id: "104512345678901",
                                       waba_id: "109876543210987", status: status, managed: true)
  end

  test "ensure_all! creates the two types once with the suggested names" do
    assert_equal %w[verification_code ticket].sort, WhatsappMessageType.pluck(:kind).sort
    assert_no_difference -> { WhatsappMessageType.count } do
      WhatsappMessageType.ensure_all!
    end

    assert_equal [ "verification_code", "es_MX", "unknown", false ], type("verification_code").then { |t| [ t.template_name, t.template_language, t.template_status, t.enabled ] }
    assert_nil type("ticket").template_name
  end

  test "the low stock notice is no longer a type: it is not created, not listed and not valid (spec 048)" do
    assert_equal %w[verification_code ticket], WhatsappMessageType::KINDS
    assert_not WhatsappMessageType.exists?(kind: "stock_alert")
    assert_not_includes WhatsappMessageType.ensure_all!.map(&:kind), "stock_alert"
    assert_not WhatsappMessageType.new(kind: "stock_alert").valid?
  end

  test "an old stock_alert row is kept but never listed, created again or counted as a type" do
    ActiveRecord::Base.connection.execute(
      "INSERT INTO whatsapp_message_types (kind, enabled, template_name, template_language, template_status, lock_version, created_at, updated_at) " \
      "VALUES ('stock_alert', TRUE, 'stock_bajo', 'es_MX', 'approved', 0, NOW(), NOW())"
    )

    assert_equal %w[ticket verification_code], WhatsappMessageType.ensure_all!.map(&:kind).sort
    assert_equal 1, WhatsappMessageType.where(kind: "stock_alert").count, "la fila vieja se conserva sin duplicarse"
  end

  test "the kind is unique and comes from the catalog" do
    assert_not WhatsappMessageType.new(kind: "verification_code").valid?
    assert_not WhatsappMessageType.new(kind: "sms").valid?
  end

  test "the template name is lowercase letters, digits and underscores, up to 512" do
    stock = type("verification_code")
    [ "Código", "codigo-x", "codigo x", "ñandú", "a" * 513 ].each do |bad|
      assert_not stock.update(template_name: bad), "#{bad.inspect} no debe valer"
    end
    assert stock.update(template_name: "verification_code_v2")
    assert stock.update(template_name: "a" * 512)
  end

  test "the language is a locale code like es_MX or es" do
    stock = type("verification_code")
    [ "español", "es-MX", "ES_mx", "e", "es_MEX" ].each { |bad| assert_not stock.update(template_language: bad), bad }
    assert stock.update(template_language: "en_US")
    assert stock.update(template_language: "es")
  end

  test "tickets do not take a template" do
    ticket = type("ticket")
    assert_not ticket.update(template_name: "algo")
    assert_not ticket.uses_template?
    assert type("verification_code").uses_template?
  end

  test "blocked_reason explains what is missing, in order" do
    stock = type("verification_code")
    assert_equal "not_connected", stock.blocked_reason

    connect!(status: "error")
    assert_equal "connection_error", stock.blocked_reason

    connect!
    assert_equal "template_not_approved", stock.blocked_reason

    stock.update!(template_status: "incompatible")
    assert_equal "template_incompatible", stock.blocked_reason

    stock.update!(template_status: "approved")
    assert_nil stock.blocked_reason
    assert stock.can_enable?
  end

  test "tickets only need a connection" do
    ticket = type("ticket")
    assert_equal "not_connected", ticket.blocked_reason
    connect!
    assert_nil ticket.blocked_reason
  end

  test "a type with a template can only be turned on when it is approved" do
    connect!
    stock = type("verification_code")

    stock.template_status = "pending"
    assert_not stock.update(enabled: true)
    assert stock.errors.of_kind?(:enabled, :template_not_approved)

    stock.update!(template_status: "approved")
    assert stock.update(enabled: true)
  end

  test "turning a type off is never blocked" do
    connect!
    stock = type("verification_code")
    stock.update!(template_status: "approved", enabled: true)
    WhatsappConnection.current.update!(status: "error")

    assert stock.reload.update(enabled: false)
  end
end
