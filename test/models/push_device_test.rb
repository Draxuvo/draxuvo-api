require "test_helper"

class PushDeviceTest < ActiveSupport::TestCase
  setup { @user = users(:resto_waiter) }

  test "register! creates and refreshes by token, and moves the device to whoever signs in" do
    device = PushDevice.register!(user: @user, token: "ExponentPushToken[abc123]", platform: "android", locale: "en")
    assert_equal "en", device.locale

    other = users(:resto_waiter2)
    moved = PushDevice.register!(user: other, token: "ExponentPushToken[abc123]", platform: "android")

    assert_equal device.id, moved.id
    assert_equal other.id, moved.reload.user_id
    assert_equal "es", moved.locale, "un idioma desconocido o ausente queda en español"
  end

  test "register! reactivates a disabled device" do
    device = register_device(@user)
    device.disable!("not_registered")

    PushDevice.register!(user: @user, token: device.token, platform: "ios")

    assert_nil device.reload.disabled_at
    assert_equal "ios", device.platform
  end

  test "rejects tokens that are not Expo push tokens" do
    assert_not PushDevice.valid_token?("abc")
    assert_not PushDevice.valid_token?("ExponentPushToken[]")
    assert PushDevice.valid_token?("ExpoPushToken[xyz]")
    assert_raises(ActiveRecord::RecordInvalid) { PushDevice.register!(user: @user, token: "fcm:123", platform: "android") }
  end

  test "never serializes the full token" do
    device = register_device(@user, token: "ExponentPushToken[secret-abcdef]")

    json = device.as_json
    assert_equal "abcdef", json[:token_hint]
    assert_not_includes json.to_s, "secret"
    assert_not_includes device.serializable_hash.keys, "token"
  end
end
