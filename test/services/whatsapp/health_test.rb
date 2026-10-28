require "test_helper"

class Whatsapp::HealthTest < ActiveSupport::TestCase
  Failure = Whatsapp::GraphClient::Failure

  setup do
    WhatsappMessageType.ensure_all!
    WhatsappConnection.current.update!(access_token: "EAAGdelpanel0000", phone_number_id: "104512345678901", waba_id: "109876543210987",
                                       status: "connected", managed: true)
    %w[verification_code stock_alert].each { |kind| WhatsappMessageType.find_by!(kind: kind).update!(template_status: "approved") }
    WhatsappConnection.current.update!(enabled: true)
    WhatsappMessageType.find_by!(kind: "stock_alert").update!(enabled: true)
    @mails = []
  end

  def connection = WhatsappConnection.current.reload

  def type(kind) = WhatsappMessageType.find_by!(kind: kind).reload

  def failure(family, reason, code) = Failure.new(family: family, reason: reason, code: code, message: "x", http_status: 400)

  def record(kind, failure, mailer: nil)
    mail = mailer || ->(user:, problem:, target:, detail:, since:, **) { @mails << { to: user.email, problem: problem, target: target, detail: detail }; { "id" => "m" } }
    ResendMailer.stub(:whatsapp_alert, mail) { Whatsapp::Health.record_failure(kind, failure) }
  end

  test "a connection failure puts the connection in error and keeps every switch as it was" do
    record(:stock_alert, failure(:connection, "token_expired", 190))

    assert_equal [ "error", "190", I18n.t("whatsapp_admin.reasons.token_expired") ], [ connection.status, connection.error_code, connection.error_message ]
    assert connection.enabled
    assert type("stock_alert").enabled
    assert_not Whatsapp::Config.current.available?("stock_alert")
  end

  test "a connection failure sends one email to every active super admin and records it" do
    second = User.create!(first_name: "Otro", last_name: "Admin", email: "otro-admin@draxuvo.test", phone: "5511112222", password: "password123", active: true, role: :super_admin)
    users(:super_admin).update_column(:active, true)
    User.create!(first_name: "Baja", last_name: "Admin", email: "baja@draxuvo.test", phone: "5511113333", password: "password123", active: false, role: :super_admin)

    record(:stock_alert, failure(:connection, "token_expired", 190))

    assert_equal [ second.email, users(:super_admin).email ].sort, @mails.map { |mail| mail[:to] }.sort
    assert_equal [ "connection" ], @mails.map { |mail| mail[:problem] }.uniq
    assert_equal [ "connection_error", "alert_sent" ], WhatsappEvent.recent.limit(2).pluck(:action).reverse
    assert_equal({ "recipients" => 2, "delivered" => 2 }, WhatsappEvent.find_by!(action: "alert_sent").data)
  end

  test "the same problem does not send another email while it lasts, and a new one after recovering does" do
    record(:stock_alert, failure(:connection, "invalid_token", 190))
    first = @mails.size
    assert_operator first, :>, 0

    record(:stock_alert, failure(:connection, "account_restricted", 368))
    assert_equal first, @mails.size, "el problema sigue: sin segundo correo"
    assert_equal "368", connection.error_code, "el motivo sí se actualiza"
    assert_equal 1, WhatsappEvent.where(action: "connection_error").count

    Whatsapp::Health.connection_recovered!
    assert_equal [ "connected", nil, nil ], [ connection.status, connection.error_code, connection.problem_notified_at ]
    assert Whatsapp::Config.current.available?("stock_alert"), "al recuperarse el canal vuelve solo"

    record(:stock_alert, failure(:connection, "invalid_token", 190))
    assert_equal first * 2, @mails.size
  end

  test "a template failure turns off only that type, marks its template and emails once" do
    WhatsappMessageType.find_by!(kind: "verification_code").update!(enabled: true)

    record(:stock_alert, failure(:template, "template_missing", 132_001))

    stock = type("stock_alert")
    assert_equal [ false, "not_found", I18n.t("whatsapp_admin.reasons.template_missing") ], [ stock.enabled, stock.template_status, stock.template_detail ]
    assert type("verification_code").enabled, "el otro tipo sigue encendido"
    assert_equal "connected", connection.status
    assert_equal [ "template" ], @mails.map { |mail| mail[:problem] }.uniq
    assert_equal [ "stock_alert" ], @mails.map { |mail| mail[:target] }.uniq
    assert_equal 1, WhatsappEvent.where(action: "auto_off", target: "stock_alert").count

    sent = @mails.size
    record(:stock_alert, failure(:template, "template_missing", 132_001))
    assert_equal sent, @mails.size, "ya está apagado y avisado"
  end

  test "template reasons map to the right template status" do
    { "template_missing" => "not_found", "template_variables" => "incompatible", "template_paused" => "rejected" }.each do |reason, status|
      type("stock_alert").update!(template_status: "approved", enabled: true, problem_notified_at: nil)
      record(:stock_alert, failure(:template, reason, 132_000))
      assert_equal status, type("stock_alert").template_status, reason
    end
  end

  test "a template failure of a type that was already off changes the status but sends no email" do
    record(:verification_code, failure(:template, "template_missing", 132_001))

    assert_equal "not_found", type("verification_code").template_status
    assert_empty @mails
    assert_equal 0, WhatsappEvent.where(action: "auto_off").count
  end

  test "a template becomes eligible to alert again once it recovers" do
    record(:stock_alert, failure(:template, "template_missing", 132_001))
    Whatsapp::Health.template_recovered!(type("stock_alert"))
    type("stock_alert").update!(template_status: "approved", enabled: true)

    sent = @mails.size
    record(:stock_alert, failure(:template, "template_missing", 132_001))
    assert_equal sent * 2, @mails.size
  end

  test "recipient and transient failures change nothing" do
    [ failure(:recipient, "outside_24h_window", 131_047), failure(:transient, "rate_limited", 130_429),
      failure(:transient, "meta_unreachable", nil), failure(:other, "unknown", 100) ].each do |fail|
      record(:stock_alert, fail)
    end

    assert_equal "connected", connection.status
    assert type("stock_alert").enabled
    assert_empty @mails
    assert_equal 0, WhatsappEvent.count
  end

  test "with only environment variables there is nowhere to store the state and nothing happens" do
    WhatsappConnection.current.update_columns(managed: false)
    with_env("WHATSAPP_ACCESS_TOKEN" => "t", "WHATSAPP_PHONE_NUMBER_ID" => "999888777") do
      record(:stock_alert, failure(:connection, "invalid_token", 190))
    end

    assert_equal "connected", connection.status
    assert_empty @mails
  end

  test "one recipient failing does not stop the others, and the event counts what was delivered" do
    User.create!(first_name: "Otro", last_name: "Admin", email: "otro-admin@draxuvo.test", phone: "5511112222", password: "password123", active: true, role: :super_admin)
    users(:super_admin).update_column(:active, true)
    calls = 0
    flaky = ->(user:, **) { calls += 1; calls == 1 ? raise("boom") : { "id" => "m" } }

    record(:stock_alert, failure(:connection, "invalid_token", 190), mailer: flaky)

    assert_equal 2, calls
    assert_equal({ "recipients" => 2, "delivered" => 1 }, WhatsappEvent.find_by!(action: "alert_sent").data)
  end

  test "Health never raises, even if everything around it breaks" do
    boom = ->(**) { raise "correo roto" }
    assert_nothing_raised { record(:stock_alert, failure(:connection, "invalid_token", 190), mailer: boom) }
    assert_equal "error", connection.status
  end

  test "no event or email carries the key" do
    record(:stock_alert, failure(:connection, "invalid_token", 190))

    assert_not WhatsappEvent.all.to_json.include?("EAAGdelpanel0000")
    assert_not @mails.to_json.include?("EAAGdelpanel0000")
  end
end
