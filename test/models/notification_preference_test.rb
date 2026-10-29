require "test_helper"

class NotificationPreferenceTest < ActiveSupport::TestCase
  setup do
    @company = companies(:pro_co)
    @user = create_member(@company, role: :owner)
  end

  test "the default is email on" do
    preference = NotificationPreference.for(@user, @company)
    assert preference.new_record?
    assert preference.stock_email
  end

  test "an old WhatsApp value needs no phone and never blocks saving (spec 048)" do
    @user.update_column(:phone, nil)
    preference = NotificationPreference.new(user: @user, company: @company, stock_whatsapp: true)

    assert preference.valid?
    assert preference.save
    assert preference.update(stock_email: false), "apagar el correo debe poder guardarse con el valor histórico"
    assert preference.reload.stock_whatsapp, "el valor histórico se conserva"
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
