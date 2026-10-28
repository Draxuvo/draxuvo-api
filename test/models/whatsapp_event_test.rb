require "test_helper"

class WhatsappEventTest < ActiveSupport::TestCase
  test "log! saves who did what and the result" do
    event = WhatsappEvent.log!(action: "channel_on", target: "connection", user: users(:super_admin), data: { from: false, to: true })

    assert_equal [ "channel_on", "connection", "ok", users(:super_admin).id ], [ event.action, event.target, event.result, event.user_id ]
    assert_equal({ "from" => false, "to" => true }, event.data)
  end

  test "log! drops secret keys at any depth so the key can never be stored" do
    event = WhatsappEvent.log!(action: "token_replaced", target: "connection",
                               data: { access_token: "EAAGsecreto", token: "x", note: "ok", nested: { secret: "y", list: [ { "token" => "z", keep: 1 } ] } })

    assert_equal({ "note" => "ok", "nested" => { "list" => [ { "keep" => 1 } ] } }, event.data)
    assert_not event.reload.to_json.include?("EAAGsecreto")
  end

  test "the action, the target and the result come from the catalog" do
    assert_raises(ActiveRecord::RecordInvalid) { WhatsappEvent.log!(action: "borrar_todo", target: "connection") }
    assert_raises(ActiveRecord::RecordInvalid) { WhatsappEvent.log!(action: "verified", target: "otro") }
    assert_raises(ActiveRecord::RecordInvalid) { WhatsappEvent.log!(action: "verified", target: "connection", result: "quizá") }
  end

  test "it is insert only: a saved event cannot be changed or deleted" do
    event = WhatsappEvent.log!(action: "verified", target: "connection")

    assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(result: "failed") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { event.destroy }
    assert_equal "ok", event.reload.result
  end

  test "mask_phone shows only the last four digits" do
    assert_equal "••••5678", WhatsappEvent.mask_phone("+52 55 1234 5678")
    assert_equal "••••5678", WhatsappEvent.mask_phone("5512345678")
    assert_nil WhatsappEvent.mask_phone(nil)
    assert_nil WhatsappEvent.mask_phone("sin números")
  end

  test "recent lists the newest first" do
    first = WhatsappEvent.log!(action: "connected", target: "connection")
    second = WhatsappEvent.log!(action: "verified", target: "connection")

    assert_equal [ second.id, first.id ], WhatsappEvent.recent.pluck(:id).first(2)
  end

  test "an event can come from the system, without a person" do
    event = WhatsappEvent.log!(action: "auto_off", target: "stock_alert", result: "failed", meta_code: 132001)

    assert_nil event.user_id
    assert_equal "132001", event.meta_code
  end
end
