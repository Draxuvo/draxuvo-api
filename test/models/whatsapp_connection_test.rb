require "test_helper"

class WhatsappConnectionTest < ActiveSupport::TestCase
  def connect!(connection = WhatsappConnection.current)
    connection.update!(access_token: "EAAGsecreto0123456789", phone_number_id: "104512345678901", waba_id: "109876543210987",
                       status: "connected", verified_name: "Draxuvo", display_phone_number: "+52 55 1234 5678", managed: true)
    connection
  end

  test "there is a single connection row that is created on first use" do
    assert_difference -> { WhatsappConnection.count }, 1 do
      WhatsappConnection.current
    end
    assert_no_difference -> { WhatsappConnection.count } do
      assert_equal WhatsappConnection.current, WhatsappConnection.current
    end
    assert_equal [ "not_connected", false, false ], WhatsappConnection.current.then { |c| [ c.status, c.enabled, c.managed ] }
  end

  test "the number and the account are only digits, 6 to 20" do
    connection = WhatsappConnection.current
    [ "12345", "1" * 21, "abc123456", "12 345 678" ].each do |bad|
      assert_not connection.update(phone_number_id: bad), "#{bad.inspect} no debe valer"
      assert_not connection.update(waba_id: bad), "#{bad.inspect} no debe valer"
    end
    assert connection.update(phone_number_id: "123456", waba_id: "1" * 20)
  end

  test "the status comes from the catalog" do
    assert_not WhatsappConnection.current.update(status: "broken")
  end

  test "the channel can only be turned on with a connected account" do
    connection = WhatsappConnection.current
    assert_not connection.update(enabled: true)
    assert connection.errors.of_kind?(:enabled, :not_connected)

    connect!(connection)
    assert connection.update(enabled: true)

    connection.update!(status: "error")
    assert connection.update(enabled: true), "ya estaba encendido: un error de conexión no borra la elección"
  end

  test "the key is stored encrypted and only the last four characters are kept readable" do
    connection = connect!
    raw = WhatsappConnection.connection.select_value("SELECT access_token FROM whatsapp_connections WHERE id = #{connection.id}")

    assert_not_includes raw, "EAAGsecreto0123456789"
    assert_equal "6789", connection.token_hint
    assert connection.token_present?
    assert_equal "EAAGsecreto0123456789", connection.reload.token
  end

  test "the key never shows up serialized or inspected" do
    connection = connect!

    assert_not connection.as_json.key?("access_token")
    assert_not connection.to_json.include?("EAAGsecreto")
    assert_not connection.inspect.include?("EAAGsecreto")
    assert_not connection.attributes_for_inspect.to_s.include?("EAAGsecreto") if connection.respond_to?(:attributes_for_inspect)
  end

  test "a key that can no longer be decrypted is reported, not raised" do
    connection = connect!
    WhatsappConnection.where(id: connection.id).update_all("access_token = 'no-es-un-texto-cifrado'")

    connection = WhatsappConnection.find(connection.id)
    assert connection.token_present?
    assert_nil connection.token
    assert connection.token_unreadable?
  end

  test "disconnecting wipes the key and the connection data, turns everything off and keeps the templates" do
    WhatsappMessageType.ensure_all!
    code = WhatsappMessageType.find_by!(kind: "verification_code")
    code.update!(template_name: "mi_plantilla", template_status: "approved")
    connection = connect!
    connection.update!(enabled: true)
    code.update!(enabled: true)

    connection.disconnect!

    connection.reload
    assert_equal [ nil, nil, nil, nil, nil, nil ], [ connection.phone_number_id, connection.waba_id, connection.token_hint, connection.verified_name, connection.display_phone_number, connection.error_code ]
    assert_not connection.token_present?
    assert_equal [ "not_connected", false, true ], [ connection.status, connection.enabled, connection.managed ]
    code.reload
    assert_not code.enabled
    assert_equal [ "mi_plantilla", "approved" ], [ code.template_name, code.template_status ]
  end

  test "the optimistic lock rejects a stale write" do
    connection = connect!
    stale = WhatsappConnection.find(connection.id)
    connection.update!(verified_name: "Uno")

    assert_raises(ActiveRecord::StaleObjectError) { stale.update!(verified_name: "Dos") }
  end
end
