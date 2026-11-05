require "test_helper"

class Push::WorkOrderAssignedTest < ActiveSupport::TestCase
  setup do
    @company = companies(:pro_co)
    @order = work_orders(:pro_open)
    @employee = employees(:pro_staff_employee)
    @staff = users(:pro_staff)
    @owner = users(:pro_co_owner)
    register_device(@staff)
  end

  def assign(order: @order, employee: @employee, actor: @owner, **args)
    Push::WorkOrderAssigned.call(work_order_id: order.id, employee_id: employee.id, actor_id: actor&.id, **args)
  end

  def open_shift!(at: Time.current)
    @employee.attendances.create!(company: @company, checkin_at: at)
  end

  test "with the shift open the assignee gets number and title, never customer data" do
    open_shift!
    fake = with_fake_expo { assert_equal :sent, assign }

    message = fake.messages.first
    assert_equal "#{@company.name} · Orden asignada", message[:title]
    assert_equal "##{@order.id} · Instalar contactos", message[:body]
    assert_equal "/ordenes/#{@order.id}", message.dig(:data, :path)
    text = message.values_at(:title, :body).join
    [ @order.customer_name, @order.customer_phone, @order.customer_address ].each { |value| assert_not_includes text, value }
  end

  test "without an open shift it is logged as off_shift and not sent" do
    fake = with_fake_expo { assert_equal :off_shift, assign }
    assert_empty fake.messages
    assert_equal "off_shift", PushDelivery.last.status

    @employee.attendances.create!(company: @company, checkin_at: 3.hours.ago, checkout_at: 1.hour.ago)
    fake = with_fake_expo { assert_equal :off_shift, assign }
    assert_empty fake.messages, "ya marcó salida"

    @employee.attendances.create!(company: @company, checkin_at: 1.day.ago)
    fake = with_fake_expo { assert_equal :off_shift, assign }
    assert_empty fake.messages, "una entrada de ayer sin salida no es turno abierto"
  end

  test "a company without the attendance module does not require a shift" do
    @company.update!(disabled_modules: [ "attendance" ])
    fake = with_fake_expo { assert_equal :sent, assign }
    assert_equal 1, fake.messages.size
  end

  test "assigning yourself, a stale assignment or an employee without user sends nothing" do
    open_shift!
    fake = with_fake_expo do
      assert_equal :skipped, assign(actor: @staff)
      assert_equal :skipped, assign(employee: employees(:pro_other_employee))
      @order.update_columns(employee_id: employees(:pro_other_employee).id)
      assert_equal :skipped, assign(employee: employees(:pro_other_employee)), "el otro técnico no tiene usuario"
    end
    assert_empty fake.messages
  end

  test "an inactive employee gets nothing" do
    open_shift!
    @employee.update_columns(status: Employee.statuses[:inactive])
    fake = with_fake_expo { assert_equal :skipped, assign }
    assert_empty fake.messages
  end
end
