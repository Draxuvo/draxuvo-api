require "test_helper"

class Push::CheckReadyJobTest < ActiveJob::TestCase
  setup do
    @round = kitchen_orders(:first_round)
    register_device(users(:resto_waiter))
  end

  test "enqueue_for waits the grouping window and enqueues one job per round" do
    assert_enqueued_jobs 1, only: Push::CheckReadyJob do
      Push::CheckReadyJob.enqueue_for([ @round.id, @round.id, nil ], users(:resto_owner).id)
    end
    job = enqueued_jobs.last
    assert_in_delta Time.current.to_f + 6, job[:at], 2
  end

  test "re-enqueues itself when the minute between notices has not passed" do
    with_fake_expo { Push::CheckReadyJob.perform_now(@round.id, users(:resto_owner).id) }
    check_items(:item_new).update_columns(status: CheckItem.statuses[:ready], ready_at: Time.current)

    assert_enqueued_jobs 1, only: Push::CheckReadyJob do
      with_fake_expo { Push::CheckReadyJob.perform_now(@round.id, users(:resto_owner).id) }
    end
  end

  test "after three transient failures it logs the notice as failed" do
    fake = PushHelpers::FakeExpo.new(raise_error: Push::ExpoClient::Transient.new("expo_http_503"))
    Push::ExpoClient.stub(:new, fake) do
      perform_enqueued_jobs do
        Push::CheckReadyJob.perform_later(@round.id, users(:resto_owner).id)
      end
    end

    delivery = PushDelivery.last
    assert_equal "failed", delivery.status
    assert_equal 3, delivery.attempts
  end
end
