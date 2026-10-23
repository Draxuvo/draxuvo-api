require "test_helper"
require Rails.root.join("db/migrate/20261023210100_backfill_employees_for_members")

# Spec 036 (R7): toda membresía tiene ficha de empleado; correr la migración dos veces no duplica.
class BackfillEmployeesForMembersTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  def run_migration = ActiveRecord::Migration.suppress_messages { BackfillEmployeesForMembers.new.up }

  test "creates the missing employee card for a member, active and without email" do
    company = companies(:pro_co)
    user = create_member(company, role: :admin)
    assert_nil company.employees.find_by(user_id: user.id)

    run_migration

    card = company.employees.find_by(user_id: user.id)
    assert_equal "active", card.status
    assert_nil card.email
    assert_includes card.name, user.first_name
  end

  test "is idempotent and keeps existing cards" do
    run_migration
    assert_no_difference -> { Employee.count } do
      run_migration
    end
    assert_equal 1, companies(:pro_co).employees.where(user: users(:pro_staff)).count
  end

  test "a user in two companies gets one card per company" do
    user = users(:pro_staff)
    other = companies(:one)
    create_member(other, role: :staff, user: user)

    run_migration

    assert other.employees.exists?(user_id: user.id)
    assert companies(:pro_co).employees.exists?(user_id: user.id)
  end
end
