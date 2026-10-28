require "test_helper"

class WhatsappMessageTypeTest < ActiveSupport::TestCase
  setup { WhatsappMessageType.ensure_all! }

  def type(kind) = WhatsappMessageType.find_by!(kind: kind)

  def connect!(status: "connected")
    WhatsappConnection.current.update!(access_token: "EAAGsecreto0123456789", phone_number_id: "104512345678901",
                                       waba_id: "109876543210987", status: status, managed: true)
  end

  test "ensure_all! creates the three types once with the suggested names" do
    assert_equal %w[verification_code stock_alert ticket].sort, WhatsappMessageType.pluck(:kind).sort
    assert_no_difference -> { WhatsappMessageType.count } do
      WhatsappMessageType.ensure_all!
    end

    assert_equal [ "verification_code", "es_MX", "unknown", false ], type("verification_code").then { |t| [ t.template_name, t.template_language, t.template_status, t.enabled ] }
    assert_equal "stock_bajo", type("stock_alert").template_name
    assert_nil type("ticket").template_name
  end

  test "the kind is unique and comes from the catalog" do
    assert_not WhatsappMessageType.new(kind: "stock_alert").valid?
    assert_not WhatsappMessageType.new(kind: "sms").valid?
  end

  test "the template name is lowercase letters, digits and underscores, up to 512" do
    stock = type("stock_alert")
    [ "Stock Bajo", "stock-bajo", "stock bajo", "ñandú", "a" * 513 ].each do |bad|
      assert_not stock.update(template_name: bad), "#{bad.inspect} no debe valer"
    end
    assert stock.update(template_name: "stock_bajo_v2")
    assert stock.update(template_name: "a" * 512)
  end

  test "the language is a locale code like es_MX or es" do
    stock = type("stock_alert")
    [ "español", "es-MX", "ES_mx", "e", "es_MEX" ].each { |bad| assert_not stock.update(template_language: bad), bad }
    assert stock.update(template_language: "en_US")
    assert stock.update(template_language: "es")
  end

  test "tickets do not take a template" do
    ticket = type("ticket")
    assert_not ticket.update(template_name: "algo")
    assert_not ticket.uses_template?
    assert type("stock_alert").uses_template?
  end

  test "blocked_reason explains what is missing, in order" do
    stock = type("stock_alert")
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
    stock = type("stock_alert")

    stock.template_status = "pending"
    assert_not stock.update(enabled: true)
    assert stock.errors.of_kind?(:enabled, :template_not_approved)

    stock.update!(template_status: "approved")
    assert stock.update(enabled: true)
  end

  test "turning a type off is never blocked" do
    connect!
    stock = type("stock_alert")
    stock.update!(template_status: "approved", enabled: true)
    WhatsappConnection.current.update!(status: "error")

    assert stock.reload.update(enabled: false)
  end
end
