require "test_helper"

class Push::CheckReadyTest < ActiveSupport::TestCase
  setup do
    @company = companies(:resto_co)
    @round = kitchen_orders(:first_round)
    @waiter = users(:resto_waiter)
    register_device(@waiter)
    # Solo el refresco está listo (hace 3 min, fixture); los otros dos quedan listos ahora.
    check_items(:item_new).update_columns(status: CheckItem.statuses[:ready], ready_at: 2.seconds.ago)
    check_items(:item_preparing).update_columns(status: CheckItem.statuses[:ready], ready_at: 1.second.ago)
  end

  def run_check_ready(**args) = Push::CheckReady.call(kitchen_order_id: @round.id, actor_id: users(:resto_owner).id, **args)

  test "groups the round's ready items in one notice for the check's waiter" do
    fake = with_fake_expo { assert_equal :sent, run_check_ready.status }

    assert_equal 1, fake.messages.size
    message = fake.messages.first
    assert_equal "Restaurante Prueba · Comanda lista", message[:title]
    assert_equal "Mesa 1 · 3 artículos listos", message[:body]
    assert_equal "/pedido?cuenta=#{checks(:open_check).id}&hoja=1", message.dig(:data, :path)
    assert_no_match(/\d+\.\d{2}|\$/, message.values_at(:title, :body).join, "sin montos")
    assert_equal "kitchen_order:#{@round.id}", PushDelivery.last.subject_key
  end

  test "a second job for the same items sends nothing new, and within a minute it asks to retry" do
    with_fake_expo { run_check_ready }

    fake = with_fake_expo do
      result = run_check_ready(now: 30.seconds.from_now)
      assert_equal :retry, result.status
      assert_in_delta PushDelivery.last.created_at + 60, result.retry_at, 1
    end
    assert_empty fake.messages

    fake = with_fake_expo { assert_equal :nothing, run_check_ready(now: 2.minutes.from_now).status }
    assert_empty fake.messages
  end

  test "jobs for the same round take a per-round lock so two at once cannot both send" do
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      with_fake_expo { run_check_ready }
    end
    assert(statements.any? { |sql| sql.include?("pg_advisory_xact_lock(#{Push::CheckReady::LOCK_NAMESPACE}, #{@round.id})") })

    # El segundo job, que esperaba el candado, ya ve el envío del primero aunque arrancó en el mismo instante.
    fake = with_fake_expo { assert_equal :retry, run_check_ready(now: PushDelivery.last.created_at - 0.1).status }
    assert_empty fake.messages
    assert_equal 1, PushDelivery.where(kind: "check_ready", status: "sent").count
  end

  test "items that became ready after the last notice get a new one" do
    with_fake_expo { run_check_ready }
    item = check_items(:item_new)
    PushDelivery.last.update_columns(created_at: 2.minutes.ago)
    CheckItem.where(kitchen_order: @round).update_all(ready_at: 3.minutes.ago)
    item.update_columns(ready_at: 1.minute.ago)

    fake = with_fake_expo { run_check_ready }
    assert_equal "Mesa 1 · 1 artículo listo", fake.messages.first[:body]
  end

  test "an old group is logged as expired instead of being sent" do
    CheckItem.where(kitchen_order: @round).update_all(ready_at: 6.minutes.ago)

    fake = with_fake_expo { assert_equal :expired, run_check_ready.status }
    assert_empty fake.messages
    assert_equal "expired", PushDelivery.last.status
  end

  test "the waiter who marks their own items ready gets nothing" do
    fake = with_fake_expo { assert_equal :skipped, Push::CheckReady.call(kitchen_order_id: @round.id, actor_id: @waiter.id).status }
    assert_empty fake.messages
  end

  test "nothing is sent for a demo company or without the restaurant module" do
    @company.update_columns(demo: true)
    fake = with_fake_expo { assert_equal :skipped, run_check_ready.status }
    assert_empty fake.messages
  end

  test "a missing round is skipped" do
    assert_equal :skipped, Push::CheckReady.call(kitchen_order_id: -1).status
  end
end
