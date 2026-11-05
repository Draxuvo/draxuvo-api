require "test_helper"

class Push::DeliverTest < ActiveSupport::TestCase
  setup do
    @company = companies(:resto_co)
    @waiter = users(:resto_waiter)
    @message = Push::Message.new(kind: "check_ready", company: @company, path: "/pedido?cuenta=1&hoja=1", subject_id: 1,
                                 body_key: "check_ready_table", body_args: { table: "1", count: 1 })
  end

  def deliver(client) = Push::Deliver.call(company: @company, user: @waiter, message: @message, subject_key: "kitchen_order:1", client: client)

  test "sends to every active device in its language and logs one row with the tickets" do
    phone = register_device(@waiter, locale: "es")
    tablet = register_device(@waiter, locale: "en")
    register_device(@waiter).disable!("stale")
    fake = PushHelpers::FakeExpo.new

    delivery = deliver(fake)

    assert_equal 2, fake.messages.size
    assert_equal [ phone.token, tablet.token ], fake.messages.map { |m| m[:to] }
    assert_equal [ "Mesa 1 · 1 artículo listo", "Table 1 · 1 item ready" ], fake.messages.map { |m| m[:body] }
    assert_equal "sent", delivery.status
    assert_equal 2, delivery.devices_count
    assert_equal [ phone.id, tablet.id ], delivery.tickets.map { |t| t["device_id"] }
    assert_not_includes delivery.attributes.to_json, phone.token, "la bitácora no guarda el token"
  end

  test "a device Expo no longer knows is disabled; if all fail that way the row is invalid_device" do
    device = register_device(@waiter)
    fake = PushHelpers::FakeExpo.new(ticket: ->(*) { { "status" => "error", "details" => { "error" => "DeviceNotRegistered" } } })

    delivery = deliver(fake)

    assert_equal "invalid_device", delivery.status
    assert_equal "not_registered", device.reload.disabled_reason
  end

  test "preference off and no devices are logged without sending" do
    fake = PushHelpers::FakeExpo.new
    assert_equal "no_devices", deliver(fake).status

    register_device(@waiter)
    NotificationPreference.for(@waiter, @company).update!(push_check_ready: false)
    assert_equal "skipped_preference", deliver(fake).status
    assert_empty fake.messages
  end

  test "someone who is not eligible is not logged at all" do
    register_device(@waiter)
    UserCompany.where(user: @waiter, company: @company).delete_all

    assert_no_difference("PushDelivery.count") { assert_nil deliver(PushHelpers::FakeExpo.new) }
  end

  test "a transient Expo failure bubbles up for the job to retry" do
    register_device(@waiter)
    fake = PushHelpers::FakeExpo.new(raise_error: Push::ExpoClient::Transient.new("expo_http_503"))

    assert_raises(Push::ExpoClient::Transient) { deliver(fake) }
    assert_equal 0, PushDelivery.count
  end
end
