require "test_helper"

class AlertDeliveryTest < ActiveSupport::TestCase
  setup do
    @company = companies(:pro_co)
    @user = create_member(@company, role: :owner)
  end

  def delivery(**attrs)
    AlertDelivery.new({ company: @company, user: @user, channel: "email", kind: "daily", status: "sent", sent_on: Date.current }.merge(attrs))
  end

  test "channel, kind and status come from the catalog" do
    assert delivery.valid?
    assert_not delivery(channel: "sms").valid?
    assert_not delivery(kind: "weekly").valid?
    assert_not delivery(status: "lost").valid?
    %w[sent failed unavailable simulated].each { |status| assert delivery(status: status).valid? }
  end

  test "the daily summary is recorded once per person, company, channel and day" do
    delivery.save!
    assert_raises(ActiveRecord::RecordNotUnique) { delivery.save! }
    assert delivery(channel: "whatsapp").save
    assert delivery(sent_on: Date.current + 1).save
  end

  test "immediate notices are not limited per day" do
    delivery(kind: "immediate").save!
    assert delivery(kind: "immediate").save
  end

  test "deleting a company deletes its alert data" do
    company = Company.create!(name: "Alertas Borrar")
    user = create_member(company, role: :admin)
    AlertSetting.create!(company: company)
    AlertSnooze.create!(company: company, kind: "table_open", subject_key: "check:9:t:1", snoozed_until: 1.hour.from_now)
    NotificationPreference.create!(user: user, company: company)
    AlertDelivery.create!(company: company, user: user, channel: "email", kind: "immediate", status: "sent", sent_on: Date.current)

    company.destroy!

    assert_equal 0, AlertSetting.where(company_id: company.id).count
    assert_equal 0, AlertSnooze.where(company_id: company.id).count
    assert_equal 0, NotificationPreference.where(company_id: company.id).count
    assert_equal 0, AlertDelivery.where(company_id: company.id).count
  end
end
