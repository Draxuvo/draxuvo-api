require "test_helper"

class StockAlertsJobsTest < ActiveJob::TestCase
  setup do
    @company = companies(:resto_co)
    @owner = create_member(@company, role: :owner)
    @company.user_companies.where.not(user_id: @owner.id).where(role: %i[owner admin]).delete_all
    @emails = []
  end

  def run_with_mail
    mail = ->(user:, kind:, products:, **) { @emails << { kind: kind, names: products.map(&:name) }; { "id" => "em_1" } }
    ResendMailer.stub(:stock_alert, mail) { yield }
  end

  test "the scan job detects, waits and then notifies on a later run" do
    run_with_mail do
      StockAlerts::ScanJob.perform_now
      assert_empty @emails
      assert_equal 1, @company.stock_alert_states.pending.count

      @company.stock_alert_states.update_all(detected_at: 10.minutes.ago)
      StockAlerts::ScanJob.perform_now
    end

    assert_equal [ [ "immediate", [ "Refresco de cola" ] ] ], @emails.map { |mail| [ mail[:kind], mail[:names] ] }
  end

  test "one company failing does not stop the others" do
    other = companies(:pro_co)
    Product.where(company_id: other.id).delete_all
    boom = ->(company, **) { raise "boom" if company.id == @company.id }
    seen = []
    StockAlerts::Scan.stub(:call, ->(company, **) { seen << company.id; boom.call(company) }) do
      StockAlerts::ScanJob.perform_now
    end
    assert_includes seen, other.id
    assert_includes seen, @company.id
  end

  test "the daily summary job sends only to companies at their hour" do
    run_with_mail do
      travel_to Time.utc(2026, 10, 28, 14, 0) do # 8:00 en Ciudad de México
        StockAlerts::DailySummaryJob.perform_now
      end
    end
    assert_equal [ "daily" ], @emails.map { |mail| mail[:kind] }.uniq

    @emails.clear
    run_with_mail do
      travel_to Time.utc(2026, 10, 28, 17, 0) do
        StockAlerts::DailySummaryJob.perform_now
      end
    end
    assert_empty @emails
  end

  test "both jobs are scheduled in production" do
    recurring = YAML.load_file(Rails.root.join("config/recurring.yml")).fetch("production")
    assert_equal "StockAlerts::ScanJob", recurring.dig("stock_alerts_scan", "class")
    assert_equal "every 5 minutes", recurring.dig("stock_alerts_scan", "schedule")
    assert_equal "StockAlerts::DailySummaryJob", recurring.dig("stock_alerts_daily_summary", "class")
    assert_equal "0 * * * *", recurring.dig("stock_alerts_daily_summary", "schedule")
  end
end
