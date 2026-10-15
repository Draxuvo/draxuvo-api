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
end
