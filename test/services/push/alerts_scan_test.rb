require "test_helper"

class Push::AlertsScanTest < ActiveSupport::TestCase
  setup do
    @company = companies(:resto_co)
    @owner = users(:resto_owner)
    @device = register_device(@owner)
    # La comanda 1 se mandó hace 15 min y los tacos siguen sin empezar: alerta «sin atender» de cocina (límite 10).
  end

  def scan(now: Time.current) = with_fake_expo { Push::AlertsScan.call(now: now) }

  def kitchen_messages(fake) = fake.messages.select { |m| m[:body].include?("sin atender") || m[:body].include?("waiting") }

  test "a new alert reaches owners and admins once, with its label and no amounts" do
    fake = scan

    message = kitchen_messages(fake).first
    assert_equal "Restaurante Prueba · Alerta", message[:title]
    assert_match(/\AMesa 1 · Comanda #1 · Cocina · 1[5-6] min sin atender\z/, message[:body])
    assert_equal "/alertas", message.dig(:data, :path)
    assert_equal "business", message[:channelId]
    assert_no_match(/\$|\d+\.\d{2}/, fake.messages.map { |m| m[:body] }.join)
    assert PushAlertNotice.exists?(company: @company, kind: "kitchen_wait")

    assert_empty kitchen_messages(scan(now: 1.minute.from_now)), "no se repite mientras siga igual"
  end

  test "staff never gets operational alerts" do
    register_device(users(:resto_waiter))
    fake = scan
    assert fake.messages.none? { |m| m[:to] != @device.token }
  end

  test "the device language decides the text" do
    @device.update!(locale: "en")
    fake = scan
    assert_match(/\ATable 1 · Order #1 · Cocina · waiting 1[5-6] min\z/, kitchen_messages(fake).first[:body])
    assert_equal "Restaurante Prueba · Alert", kitchen_messages(fake).first[:title]
  end

  test "a snoozed alert is not sent and comes back once when the snooze ends" do
    alert = Alerts::Collector.new(@company).call.results.find { |a| a.kind == "kitchen_wait" }
    snooze = AlertSnooze.create!(company: @company, user: @owner, kind: "kitchen_wait", subject_key: alert.subject_key,
                                 snoozed_until: 30.minutes.from_now)

    assert_empty kitchen_messages(scan)
    assert PushAlertNotice.find_by(company: @company, kind: "kitchen_wait").rearm

    snooze.update_columns(snoozed_until: 1.minute.ago)
    assert_equal 1, kitchen_messages(scan).size
    assert_empty kitchen_messages(scan), "una sola vez al terminar la posposición"
  end

  test "an element that advances is forgotten, and a different kind of alert is a new notice" do
    scan
    check_items(:item_new).update_columns(status: CheckItem.statuses[:preparing], preparing_at: 30.minutes.ago)

    fake = scan
    assert_empty kitchen_messages(fake)
    assert_not PushAlertNotice.exists?(company: @company, kind: "kitchen_wait")
    assert(fake.messages.any? { |m| m[:body].include?("en preparación") }, "ahora tarda en preparación: aviso nuevo")
  end

  test "companies without push-ready bosses, demos or with the kind turned off are not scanned" do
    NotificationPreference.for(@owner, @company).update!(push_operational_alerts: false)
    assert_not_includes Push::AlertsScan.new(Time.current).companies, @company

    NotificationPreference.for(@owner, @company).update!(push_operational_alerts: true)
    @company.update_columns(demo: true)
    assert_not_includes Push::AlertsScan.new(Time.current).companies, @company
  end

  test "an Expo failure leaves the alert unmarked to retry on the next scan" do
    Push::ExpoClient.stub(:new, PushHelpers::FakeExpo.new(raise_error: Push::ExpoClient::Transient.new("expo_http_503"))) do
      Push::AlertsScan.call
    end
    assert_not PushAlertNotice.exists?(company: @company, kind: "kitchen_wait")
    assert_equal 1, kitchen_messages(scan).size
  end
end
