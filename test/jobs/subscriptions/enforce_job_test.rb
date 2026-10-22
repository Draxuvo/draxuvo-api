require "test_helper"

# Spec 031, R4: gracia de 7 días, aviso a los 23 y cancelación automática a los 30 de suspendida.
class Subscriptions::EnforceJobTest < ActiveJob::TestCase
  setup do
    @sent = []
  end

  def run_job(&extra)
    ResendMailer.stub(:subscription_notice, ->(**args) { @sent << args; { "id" => "email_1" } }) do
      Stripe::Subscription.stub(:cancel, extra || ->(*) { Stripe::StripeObject.construct_from(status: "canceled") }) do
        Subscriptions::EnforceJob.perform_now
      end
    end
  end

  test "a past due subscription inside the 7 days keeps operating" do
    subscription = subscriptions(:past_due_co)
    subscription.update_columns(past_due_since: 6.days.ago)

    run_job

    assert subscription.reload.past_due?
  end

  test "a past due subscription past the 7 days is suspended for overdue payment" do
    subscription = subscriptions(:past_due_co)
    subscription.update_columns(past_due_since: 8.days.ago)

    run_job

    subscription.reload
    assert subscription.suspended?
    assert_equal "payment_overdue", subscription.suspension_reason
    assert_equal "suspended", subscription.subscription_changes.last.kind
    assert @sent.any? { |mail| mail[:kind] == "suspended" }
  end

  test "a subscription suspended 24 days is warned once before the automatic cancellation" do
    subscription = subscriptions(:pro_co)
    subscription.update_columns(status: Subscription.statuses[:suspended], suspended_at: 24.days.ago, suspension_reason: "plan_change")

    run_job
    first = @sent.count { |mail| mail[:kind] == "cancel_warning" }
    run_job

    assert first.positive?
    assert_equal first, @sent.count { |mail| mail[:kind] == "cancel_warning" }
    assert subscription.reload.suspended?
    assert_not_nil subscription.cancel_warning_sent_at
  end

  test "a subscription suspended 31 days is cancelled in Stripe and locally and recorded" do
    subscription = subscriptions(:pro_co)
    subscription.update_columns(status: Subscription.statuses[:suspended], suspended_at: 31.days.ago, suspension_reason: "plan_change")
    cancelled = []

    run_job { |id, *| cancelled << id; Stripe::StripeObject.construct_from(status: "canceled") }

    subscription.reload
    assert subscription.cancelled?
    assert_equal [ "sub_pro" ], cancelled
    change = subscription.subscription_changes.last
    assert_equal [ "auto_cancelled", "plan_change" ], [ change.kind, change.reason ]
  end

  test "a subscription suspended less than 23 days is left alone" do
    subscription = subscriptions(:pro_co)
    subscription.update_columns(status: Subscription.statuses[:suspended], suspended_at: 10.days.ago, suspension_reason: "plan_change")

    run_job

    assert subscription.reload.suspended?
    assert_empty @sent
  end
end
