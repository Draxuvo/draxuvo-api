require "test_helper"

class Registrations::CreateServiceTest < ActiveSupport::TestCase
  def params(**overrides)
    { company_name: "Café Ana", first_name: "Ana", last_name: "López", phone: "5511223344",
      email: "ana@cafe-ana.test", password: "secreto123", plan: "pro", billing_cycle: "monthly" }.merge(overrides)
  end

  def register(**overrides)
    Registrations::CreateService.new(params(**overrides)).call
  end

  test "creates the company, an active owner, the membership and the trial subscription" do
    result = register
    assert_equal "Café Ana", result.company.name
    assert_equal "cafe-ana", result.company.slug
    assert result.user.persisted?
    assert result.user.active?
    assert_equal "owner", result.user.role_in(result.company)
    assert_equal result.company.subscription, result.subscription
    assert result.subscription.trialing?
    assert result.subscription.pro?
    assert result.subscription.monthly?
  end

  test "applies the chosen plan and billing cycle to the subscription" do
    result = register(plan: "enterprise", billing_cycle: "annual", email: "e@cafe-ana.test")
    assert result.subscription.reload.enterprise?
    assert result.subscription.annual?
  end

  test "billing cycle defaults to monthly" do
    assert register(billing_cycle: nil).subscription.monthly?
  end

  test "accepts string keys" do
    stringified = params.stringify_keys
    assert Registrations::CreateService.new(stringified).call.company.persisted?
  end

  test "adds a numeric suffix when the slug already exists" do
    first = register
    second = register(email: "otra@cafe-ana.test")
    third = register(email: "tercera@cafe-ana.test")
    assert_equal "cafe-ana", first.company.slug
    assert_equal "cafe-ana-2", second.company.slug
    assert_equal "cafe-ana-3", third.company.slug
  end

  test "rejects an invalid plan without creating anything" do
    assert_no_difference [ "Company.count", "User.count" ] do
      assert_raises(ApiErrors::BadRequestError) { register(plan: "gold") }
      assert_raises(ApiErrors::BadRequestError) { register(plan: nil) }
    end
  end

  test "rejects an invalid billing cycle" do
    error = assert_raises(ApiErrors::BadRequestError) { register(billing_cycle: "weekly") }
    assert_equal I18n.t("errors.subscription.invalid_billing_cycle"), error.details
  end

  test "rejects an email that is already registered" do
    register
    assert_no_difference [ "Company.count", "User.count" ] do
      error = assert_raises(ApiErrors::UnprocessableEntityError) { register(company_name: "Otra Empresa") }
      assert error.details.any? { |message| message.downcase.include?("email") }
    end
  end

  test "rejects a missing company name and reports every error" do
    error = assert_raises(ApiErrors::UnprocessableEntityError) do
      register(company_name: "", first_name: "", password: "123")
    end
    assert_operator error.details.size, :>=, 3
    assert_equal I18n.t("errors.validation_failed"), error.message
  end

  test "a failure after validation leaves nothing behind" do
    UserCompany.stub(:create!, ->(*) { raise ActiveRecord::RecordInvalid }) do
      assert_no_difference [ "Company.count", "User.count", "Subscription.count" ] do
        assert_raises(ActiveRecord::RecordInvalid) { register }
      end
    end
  end

  test "ignores unknown fields such as role" do
    result = register(role: "super_admin")
    assert result.user.staff?
    assert_equal "owner", result.user.role_in(result.company)
  end
end
