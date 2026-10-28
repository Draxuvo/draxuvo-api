require "test_helper"

class StockAlerts::ScanDispatchTest < ActiveSupport::TestCase
  setup do
    @company = companies(:resto_co)
    @owner = create_member(@company, role: :owner)
    @company.user_companies.where.not(user_id: @owner.id).where(role: %i[owner admin]).delete_all # solo mi dueño recibe
    @cola = products(:resto_cola) # stock 2, mínimo 3: ya está bajo
    @tacos = products(:resto_tacos) # stock 10, mínimo 3
    @emails = []
    @whatsapps = []
  end

  # Corre el bloque con los dos canales simulados y recoge lo que se mandó.
  def with_channels(&block)
    mail = ->(user:, company_name:, kind:, products:, **) { @emails << { user: user, kind: kind, products: products.map(&:name) }; { "id" => "em_1" } }
    ResendMailer.stub(:stock_alert, mail) do
      Whatsapp::StockAlertService.stub(:new, ->(**args) { FakeWhatsapp.new(@whatsapps, args) }, &block)
    end
  end

  FakeWhatsapp = Struct.new(:log, :args) do
    def call
      log << args
      Whatsapp::StockAlertService::Result.new(status: "sent")
    end
  end

  def scan_at(time) = StockAlerts::Scan.call(@company, now: time)

  def dispatch_at(time) = StockAlerts::Dispatch.call(@company, now: time)

  def lower(product, stock) = Product.where(id: product.id).update_all(stock: stock)

  test "the scan records products that are low and ignores the rest" do
    scan_at(Time.current)
    assert_equal [ @cola.id ], @company.stock_alert_states.pluck(:product_id)
    assert_nil @company.stock_alert_states.first.notified_at
  end

  test "it waits for the grace period and then notifies once, all products in one message" do
    lower(@tacos, 1)
    t0 = Time.current
    scan_at(t0)

    with_channels do
      dispatch_at(t0 + 4.minutes)
      assert_empty @emails

      dispatch_at(t0 + 6.minutes)
      assert_equal 1, @emails.size
      assert_equal [ "Refresco de cola", "Tacos al pastor" ].sort, @emails.first[:products].sort
      assert_equal "immediate", @emails.first[:kind]
      assert_equal @owner, @emails.first[:user]

      dispatch_at(t0 + 30.minutes)
      assert_equal 1, @emails.size, "no se repite mientras siga bajo"
    end

    assert_equal 2, @company.stock_alert_states.notified.count
    assert_equal [ "sent" ], @company.alert_deliveries.where(channel: "email").pluck(:status).uniq
  end

  test "a restocked product is rearmed and notifies again when it drops once more" do
    t0 = Time.current
    scan_at(t0)
    with_channels { dispatch_at(t0 + 6.minutes) }
    assert_equal 1, @emails.size

    lower(@cola, 20)
    scan_at(t0 + 10.minutes)
    assert_equal 0, @company.stock_alert_states.count

    lower(@cola, 1)
    scan_at(t0 + 15.minutes)
    with_channels { dispatch_at(t0 + 21.minutes) }
    assert_equal 2, @emails.size
  end

  test "a bulk drop is grouped in a single notice per person" do
    Product.where(company_id: @company.id).counted.update_all(stock: 0, min_stock: 5)
    t0 = Time.current
    scan_at(t0)

    with_channels { dispatch_at(t0 + 6.minutes) }
    assert_equal 1, @emails.size
    assert_equal 2, @emails.first[:products].size
  end

  test "WhatsApp goes only to people who turned it on and have a phone" do
    NotificationPreference.create!(user: @owner, company: @company, stock_email: false, stock_whatsapp: true)
    t0 = Time.current
    scan_at(t0)

    with_channels { dispatch_at(t0 + 6.minutes) }
    assert_empty @emails
    assert_equal 1, @whatsapps.size
    assert_equal @owner.phone, @whatsapps.first[:phone]
    assert_equal [ [ "whatsapp", "sent" ] ], @company.alert_deliveries.pluck(:channel, :status)
  end

  test "with nobody to notify the products are still marked as notified" do
    @company.user_companies.where(user_id: @owner.id).delete_all
    t0 = Time.current
    scan_at(t0)

    with_channels { dispatch_at(t0 + 6.minutes) }
    assert_empty @emails
    assert_equal 1, @company.stock_alert_states.notified.count
  end

  test "a time alert alone never sends an email or a WhatsApp" do
    Product.where(company_id: @company.id).update_all(stock: 1000)
    Check.where(id: checks(:open_check).id).update_all(opened_at: 5.hours.ago)
    assert_equal 1, Alerts::Collector.new(@company).call.results.count { |alert| alert.kind == "table_open" }

    t0 = Time.current
    scan_at(t0)
    with_channels { dispatch_at(t0 + 30.minutes) }
    assert_empty @emails
    assert_empty @whatsapps
    assert_equal 0, AlertDelivery.count
  end

  test "only real companies with inventory and a subscription with access are scanned" do
    ids = []
    StockAlerts::Companies.each { |company| ids << company.id }
    assert_includes ids, @company.id

    @company.update!(disabled_modules: [ "inventory" ])
    ids = []
    StockAlerts::Companies.each { |company| ids << company.id }
    assert_not_includes ids, @company.id
  end

  test "demo, suspended and cancelled companies are skipped" do
    demo = Company.create!(name: "Demo Stock", demo: true)
    ids = []
    StockAlerts::Companies.each { |company| ids << company.id }
    assert_not_includes ids, demo.id

    @company.subscription.update_columns(status: Subscription.statuses.fetch("suspended"))
    ids = []
    StockAlerts::Companies.each { |company| ids << company.id }
    assert_not_includes ids, @company.id

    @company.subscription.update_columns(status: Subscription.statuses.fetch("cancelled"))
    ids = []
    StockAlerts::Companies.each { |company| ids << company.id }
    assert_not_includes ids, @company.id
  end
end
