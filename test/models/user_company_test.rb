require "test_helper"

class UserCompanyTest < ActiveSupport::TestCase
  test "role defaults to staff" do
    membership = UserCompany.create!(user: users(:pro_staff), company: companies(:basic_co))
    assert membership.staff?
  end

  test "a user can only belong once to a company" do
    duplicate = UserCompany.new(user: users(:pro_staff), company: companies(:pro_co))
    assert_not duplicate.valid?
    assert duplicate.errors[:user_id].any?
  end

  test "the same user can belong to different companies" do
    assert UserCompany.new(user: users(:pro_staff), company: companies(:basic_co), role: :manager).valid?
  end

  test "requires user and company" do
    membership = UserCompany.new
    assert_not membership.valid?
    assert membership.errors[:user].any?
    assert membership.errors[:company].any?
  end

  test "rank orders roles from staff up to super_admin" do
    ranks = %w[staff manager admin owner super_admin].map { |role| UserCompany.rank(role) }
    assert_equal ranks.sort, ranks
    assert_equal 4, UserCompany.rank("super_admin")
    assert_equal 0, UserCompany.rank(:staff)
  end

  test "rank of an unknown or nil role is -1" do
    assert_equal(-1, UserCompany.rank("intruso"))
    assert_equal(-1, UserCompany.rank(nil))
  end

  test "fixtures expose the role enum" do
    assert user_companies(:pro_manager).manager?
    assert user_companies(:pro_co_owner).owner?
  end

  # --- Spec 036: toda persona con acceso tiene ficha de empleado ---

  test "giving staff access creates an active employee card for the person" do
    company = companies(:pro_co)
    user = User.create!(first_name: "Marta", last_name: "Gómez", email: "marta@ficha.test", phone: "5512340000", password: "password123", active: true)

    assert_difference -> { company.employees.count }, 1 do
      UserCompany.create!(user: user, company: company, role: :staff)
    end

    card = company.employees.find_by!(user_id: user.id)
    assert_equal "active", card.status
    assert_includes card.name, "Marta"
  end

  test "managers, admins and owners get no employee card" do
    company = companies(:pro_co)
    %i[manager admin owner].each do |role|
      user = create_member(company, role: role)
      assert_not company.employees.exists?(user_id: user.id), "#{role} no es personal"
    end
  end

  test "becoming staff creates the card and Employee.team leaves bosses out" do
    company = companies(:pro_co)
    user = create_member(company, role: :manager)
    membership = company.user_companies.find_by!(user: user)

    assert_difference -> { company.employees.count }, 1 do
      membership.update!(role: :staff)
    end
    card = company.employees.find_by!(user_id: user.id)
    assert_includes company.employees.team, card

    membership.update!(role: :admin)
    assert_not_includes company.employees.team, card
    assert Employee.exists?(card.id)
  end

  test "an existing card of the person is reused" do
    company = companies(:pro_co)
    user = create_member(company, role: :staff, employee: false)
    company.employees.create!(name: "Ya existe", status: :active, user: user)
    company.user_companies.find_by(user: user).destroy!
    company.employees.create!(name: "Ya existe", status: :active, user: user)

    assert_no_difference -> { company.employees.count } do
      UserCompany.create!(user: user, company: company, role: :staff)
    end
  end

  test "removing access releases the card but keeps it with its attendance" do
    company = companies(:pro_co)
    user = create_member(company, role: :staff)
    card = company.employees.find_by!(user_id: user.id)
    card.attendances.create!(company: company, checkin_at: 1.hour.ago)

    company.user_companies.find_by!(user: user).destroy!

    assert_nil card.reload.user_id
    assert_equal 1, card.attendances.count
  end
end
