require "test_helper"

# Spec 031: suspender, reactivar y avisar por falta de pago.
class Subscriptions::SuspensionServicesTest < ActiveSupport::TestCase
  setup do
    @subscription = subscriptions(:pro_co)
    @sent = []
  end

  def deliver(&block)
    ResendMailer.stub(:subscription_notice, ->(**args) { @sent << args; { "id" => "email_1" } }, &block)
  end

  test "suspend leaves the subscription suspended with its reason, the invoice url and a record" do
    deliver { Subscriptions::SuspendService.new(@subscription, reason: "plan_change", invoice_url: "https://invoice.test/1").call }

    @subscription.reload
    assert @subscription.suspended?
    assert_not @subscription.active_access?
    assert_equal "plan_change", @subscription.suspension_reason
    assert_equal "https://invoice.test/1", @subscription.pending_invoice_url
    assert_in_delta 30.days.from_now.to_f, @subscription.cancels_at.to_f, 5
    change = @subscription.subscription_changes.last
    assert_equal [ "suspended", "plan_change" ], [ change.kind, change.reason ]
    assert_nil change.actor_id
  end

  test "suspend warns the owners and admins once and is idempotent" do
    deliver do
      Subscriptions::SuspendService.new(@subscription, reason: "plan_change").call
      Subscriptions::SuspendService.new(@subscription.reload, reason: "plan_change").call
    end

    assert_equal 1, @subscription.subscription_changes.where(kind: "suspended").count
    assert @sent.any?
    assert_equal [ "suspended" ], @sent.map { |mail| mail[:kind] }.uniq
    recipients = @sent.map { |mail| mail[:user] }
    assert recipients.all? { |user| @subscription.company.user_companies.where(user: user, role: %i[owner admin]).exists? }
  end

  test "reactivate clears the suspension and records it" do
    deliver { Subscriptions::SuspendService.new(@subscription, reason: "plan_change", invoice_url: "https://invoice.test/1").call }

    Subscriptions::ReactivateService.new(@subscription.reload).call

    @subscription.reload
    assert @subscription.active?
    assert @subscription.active_access?
    assert_nil @subscription.suspended_at
    assert_nil @subscription.suspension_reason
    assert_nil @subscription.pending_invoice_url
    assert_equal "reactivated", @subscription.subscription_changes.last.kind
  end

  test "reactivate does nothing to a subscription that was not suspended" do
    assert_no_difference -> { SubscriptionChange.count } do
      Subscriptions::ReactivateService.new(@subscription).call
    end
    assert @subscription.reload.active?
  end

  test "notify sends the past due notice only once" do
    @subscription.update!(status: :past_due, past_due_since: Time.current)

    deliver do
      Subscriptions::NotifyService.new(@subscription, "past_due").call
      Subscriptions::NotifyService.new(@subscription.reload, "past_due").call
    end

    first_round = @sent.map { |mail| mail[:user].id }.uniq.size
    assert_equal first_round, @sent.size
    assert_not_nil @subscription.reload.past_due_notice_sent_at
  end
end
