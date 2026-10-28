require "test_helper"

class StockAlerts::DailySummaryTest < ActiveSupport::TestCase
  setup do
    @company = companies(:resto_co)
    @owner = create_member(@company, role: :owner)
    @company.user_companies.where.not(user_id: @owner.id).where(role: %i[owner admin]).delete_all
    @emails = []
    # 8:00 de la Ciudad de México (UTC-6 en octubre de 2026 tras el fin del horario de verano)
    @eight = Time.utc(2026, 10, 28, 14, 0).in_time_zone("America/Mexico_City")
  end

  def summary(time)
    mail = ->(user:, kind:, products:, **) { @emails << { user: user, kind: kind, names: products.map(&:name) }; { "id" => "em_1" } }
    ResendMailer.stub(:stock_alert, mail) { StockAlerts::DailySummary.call(@company, now: time) }
  end

  test "at the configured hour it sends everything that is still low, in one message" do
    summary(@eight)
    assert_equal 1, @emails.size
    assert_equal [ "daily", [ "Refresco de cola" ] ], [ @emails.first[:kind], @emails.first[:names] ]
    assert_equal [ [ "email", "daily", "sent" ] ], @company.alert_deliveries.pluck(:channel, :kind, :status)
  end

  test "it includes products already notified earlier but still low" do
    StockAlertState.create!(company: @company, product: products(:resto_cola), detected_at: 1.day.ago, notified_at: 1.day.ago)
    summary(@eight)
    assert_equal [ "Refresco de cola" ], @emails.first[:names]
  end

  test "outside the configured hour it sends nothing" do
    summary(@eight + 1.hour)
    summary(@eight - 1.hour)
    assert_empty @emails
  end

  test "the hour follows the company's own setting and time zone" do
    AlertSetting.create!(company: @company, summary_hour: 9, time_zone: "America/Tijuana")
    summary(@eight) # 8:00 en CDMX = 7:00 en Tijuana
    assert_empty @emails

    summary(Time.utc(2026, 10, 28, 16, 0)) # 9:00 en Tijuana (UTC-7)
    assert_equal 1, @emails.size
  end

  test "it never sends twice on the same day" do
    summary(@eight)
    summary(@eight + 10.minutes)
    assert_equal 1, @emails.size
    assert_equal 1, @company.alert_deliveries.count

    summary(@eight + 1.day)
    assert_equal 2, @emails.size
  end

  test "with nothing low it sends nothing" do
    Product.where(company_id: @company.id).update_all(stock: 1000)
    summary(@eight)
    assert_empty @emails
    assert_equal 0, AlertDelivery.count
  end
end
