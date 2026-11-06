require "test_helper"

# Spec 058 (US3 y US4, FR-021): aviso «Por cobrar» a dueño y administradores.
class Push::ChargePendingTest < ActiveSupport::TestCase
  setup do
    @company = companies(:pos_co)
    @company.update!(boss_only_charge: true)
    @owner = users(:pos_owner)
    @admin = users(:pos_admin)
    @staff = users(:pos_staff)
    [ @owner, @admin, @staff ].each { |user| register_device(user) }
    @sale = open_sale(@staff, [ products(:pos_cuaderno), 1 ])
    @sale.update!(submitted_at: Time.current)
  end

  def notify(type: "sale", id: @sale.id, actor: @staff)
    Push::ChargePending.call(subject_type: type, subject_id: id, actor_id: actor&.id)
  end

  test "a sale sent to charge notifies owner and admin, not staff, without amounts" do
    fake = with_fake_expo { notify }

    assert_equal 2, fake.messages.size
    message = fake.messages.first
    assert_equal "#{@company.name} · Por cobrar", message[:title]
    assert_includes message[:body], @staff.full_name
    assert_not_includes message[:body], @sale.total.to_s
    assert_not_includes message[:body], "$"
    assert_equal "/venta?venta=#{@sale.id}", message.dig(:data, :path)
    assert_equal "charge_pending", message.dig(:data, :kind)
    assert_equal [ "sale:#{@sale.id}:#{@sale.submitted_at.to_i}" ], PushDelivery.where(kind: "charge_pending").distinct.pluck(:subject_key)
    assert_equal [ @admin.id, @owner.id ].sort, PushDelivery.where(kind: "charge_pending").pluck(:user_id).sort
  end

  test "the actor does not notify itself" do
    fake = with_fake_expo { notify(actor: @admin) }
    assert_equal 1, fake.messages.size
    assert_equal [ @owner.id ], PushDelivery.where(kind: "charge_pending").pluck(:user_id)
  end

  test "a boss who turned it off is logged as skipped" do
    NotificationPreference.for(@admin, @company).tap { |pref| pref.push_charge_pending = false }.save!
    fake = with_fake_expo { notify }
    assert_equal 1, fake.messages.size
    assert_equal "skipped_preference", PushDelivery.find_by(user: @admin, kind: "charge_pending").status
  end

  test "nothing is sent with the option off or in a demo" do
    @company.update!(boss_only_charge: false)
    fake = with_fake_expo { notify }
    assert_empty fake.messages

    @company.update!(boss_only_charge: true, demo: true)
    fake = with_fake_expo { notify }
    assert_empty fake.messages
  end

  test "a done work order points to the order" do
    company = companies(:pro_co)
    company.update!(boss_only_charge: true)
    owner = users(:pro_co_owner)
    register_device(owner)
    order = work_orders(:pro_done)
    order.update_columns(customer_name: "Café La Plaza")

    fake = with_fake_expo { Push::ChargePending.call(subject_type: "work_order", subject_id: order.id, actor_id: nil) }
    message = fake.messages.find { |m| m.dig(:data, :path) == "/ordenes/#{order.id}" }
    assert message
    assert_equal "Orden ##{order.id} lista para cobrar", message[:body]
    assert_not_includes message[:body], "Café La Plaza"
  end

  test "a takeout check is named by its number, not by the customer" do
    company = companies(:resto_co)
    company.update!(boss_only_charge: true)
    owner = users(:resto_owner)
    register_device(owner)
    check = checks(:takeout_check)
    check.update_columns(charge_requested_at: Time.current)

    fake = with_fake_expo { Push::ChargePending.call(subject_type: "check", subject_id: check.id, actor_id: users(:resto_waiter2).id) }
    message = fake.messages.first
    assert_equal "Cuenta para llevar ##{check.id} pidió cobro", message[:body]
    assert_not_includes message[:body], check.takeout_name
    assert_equal "/pedido?cuenta=#{check.id}&hoja=1", message.dig(:data, :path)
  end

  test "a table check names the table" do
    company = companies(:resto_co)
    company.update!(boss_only_charge: true)
    register_device(users(:resto_owner))
    check = checks(:open_check)
    check.update_columns(charge_requested_at: Time.current)

    fake = with_fake_expo { Push::ChargePending.call(subject_type: "check", subject_id: check.id, actor_id: nil) }
    assert_equal "Mesa #{check.dining_table.name} pidió la cuenta", fake.messages.first[:body]
  end
end
