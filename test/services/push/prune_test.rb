require "test_helper"

class Push::PruneTest < ActiveSupport::TestCase
  test "disables phones unseen for 30 days and deletes deliveries older than 90 days" do
    user = users(:resto_waiter)
    fresh = register_device(user)
    stale = register_device(user).tap { |device| device.update_columns(last_seen_at: 31.days.ago) }
    old = PushDelivery.create!(company: companies(:resto_co), user: user, kind: "check_ready", subject_key: "x", status: "sent",
                               created_at: 91.days.ago)
    recent = PushDelivery.create!(company: companies(:resto_co), user: user, kind: "check_ready", subject_key: "y", status: "sent")

    Push::Prune.call

    assert_nil fresh.reload.disabled_at
    assert_equal "stale", stale.reload.disabled_reason
    assert_not PushDelivery.exists?(old.id)
    assert PushDelivery.exists?(recent.id)
  end

  test "a phone that registers again is active again" do
    device = register_device(users(:resto_waiter)).tap { |d| d.update_columns(last_seen_at: 31.days.ago) }
    Push::Prune.call

    PushDevice.register!(user: device.user, token: device.token, platform: "android")
    assert_nil device.reload.disabled_at
  end
end
