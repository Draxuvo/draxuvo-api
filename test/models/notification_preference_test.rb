require "test_helper"

class NotificationPreferenceTest < ActiveSupport::TestCase
  setup do
    @company = companies(:pro_co)
    @user = create_member(@company, role: :owner)
  end

  test "defaults are email on and WhatsApp off" do
    preference = NotificationPreference.for(@user, @company)
    assert preference.new_record?
    assert preference.stock_email
    assert_not preference.stock_whatsapp
  end

  test "WhatsApp needs a phone number" do
    @user.update_column(:phone, nil)
    preference = NotificationPreference.new(user: @user, company: @company, stock_whatsapp: true)
    assert_not preference.valid?
    assert preference.errors.of_kind?(:stock_whatsapp, :phone_required)

    @user.update_column(:phone, "5512340000")
    assert NotificationPreference.new(user: @user.reload, company: @company, stock_whatsapp: true).valid?
  end

  test "one row per person and company, so the same person can differ between companies" do
    NotificationPreference.create!(user: @user, company: @company, stock_email: false)
    assert_not NotificationPreference.new(user: @user, company: @company).valid?

    other = companies(:one)
    UserCompany.create!(user: @user, company: other, role: :admin)
    assert NotificationPreference.new(user: @user, company: other).valid?
    assert_equal false, NotificationPreference.for(@user, @company).stock_email
    assert_equal true, NotificationPreference.for(@user, other).stock_email
  end
end
