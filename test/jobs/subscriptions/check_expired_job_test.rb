require "test_helper"

class Subscriptions::CheckExpiredJobTest < ActiveJob::TestCase
  test "expires only trials whose trial ended and leaves paid subscriptions alone" do
    ended_trial = subscriptions(:one)
    ended_trial.update_columns(trial_ends_at: 1.day.ago)
    running_trial = subscriptions(:two)
    subscriptions(:past_due_co).update_columns(trial_ends_at: 10.days.ago)

    Subscriptions::CheckExpiredJob.perform_now

    assert ended_trial.reload.expired?
    assert running_trial.reload.trialing?
    assert subscriptions(:pro_co).reload.active?
    assert subscriptions(:basic_co).reload.active?
    assert subscriptions(:past_due_co).reload.past_due?
  end
end
