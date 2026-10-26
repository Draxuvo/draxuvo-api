require "test_helper"

class DemoInviteTest < ActiveSupport::TestCase
  def issue(**overrides)
    DemoInvite.issue!(plan: "pro", scenario: "pro_restaurant", label: "Café La Plaza", **overrides)
  end

  test "issue! returns the token once and stores only its SHA-256 digest" do
    invite, token = issue

    assert_operator token.length, :>=, 40
    assert_equal Digest::SHA256.hexdigest(token), invite.token_digest
    assert_not_includes invite.attributes.values.map(&:to_s), token
    assert_equal invite, DemoInvite.find_by_token(token)
    assert_nil DemoInvite.find_by_token("otro")
    assert_nil DemoInvite.find_by_token(nil)
  end

  test "digests are unique" do
    invite, = issue
    twin = DemoInvite.new(plan: "pro", scenario: "pro_restaurant", label: "Otro", token_digest: invite.token_digest,
                          expires_at: 1.day.from_now)

    assert_not twin.valid?
    assert twin.errors.of_kind?(:token_digest, :taken)
  end

  test "a scenario of another plan is invalid" do
    invite = DemoInvite.new(plan: "basic", scenario: "pro_service", label: "Ana", token_digest: "x", expires_at: 1.day.from_now)

    assert_not invite.valid?
    assert invite.errors[:scenario].any?
  end

  test "the label must have between 2 and 120 characters" do
    assert_raises(ActiveRecord::RecordInvalid) { issue(label: "A") }
    assert_raises(ActiveRecord::RecordInvalid) { issue(label: "a" * 121) }
    assert_nothing_raised { issue(label: "ab") }
    assert_nothing_raised { issue(label: "a" * 120) }
  end

  test "it cannot be created already expired" do
    assert_raises(ActiveRecord::RecordInvalid) { issue(expires_at: 1.minute.ago) }
  end

  test "the status is active, expired or revoked, and revoking wins over expiring" do
    invite, = issue
    assert_equal "active", invite.status
    assert invite.active?

    invite.update_columns(expires_at: 1.minute.ago)
    assert_equal "expired", invite.status

    invite.revoke!
    assert_equal "revoked", invite.status
    assert_not invite.active?
  end

  test "revoke! is idempotent and keeps the first revocation time" do
    invite, = issue
    first = invite.revoke!.revoked_at

    travel 1.hour do
      assert_equal first, invite.revoke!.revoked_at
    end
  end

  test "defaults to the configured number of days" do
    invite, = issue

    assert_in_delta Demo::Config.invite_days.days.from_now.to_i, invite.expires_at.to_i, 5
  end
end
