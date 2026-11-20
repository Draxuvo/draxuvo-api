require "test_helper"

# Spec 069, FR-030 y research R13: la conexión pasa a «Con error» y se avisa una vez por cambio de estado.
class TerminalConnections::HealthTest < ActiveSupport::TestCase
  setup do
    @connection = terminal_connection_for(companies(:pro_co))
  end

  def failure(family = :connection, reason = "unauthorized")
    TerminalProviders::Failure.new(family: family, reason: reason)
  end

  def capture_emails
    sent = []
    Resend::Emails.stub(:send, ->(params) { sent << params; resend_response }) { yield }
    sent
  end

  test "un fallo de conexión marca el error y avisa una sola vez a dueño y administradores" do
    sent = capture_emails do
      TerminalConnections::Health.failed!(@connection, failure)
      TerminalConnections::Health.failed!(@connection.reload, failure)
    end
    @connection.reload
    assert @connection.error?
    assert_equal "unauthorized", @connection.error_code
    assert @connection.problem_notified_at
    recipients = sent.map { |email| email[:to] }
    owners = companies(:pro_co).user_companies.where(role: %i[owner admin]).includes(:user).map { |m| m.user.email }
    assert_equal owners.sort, recipients.sort
    assert_match "Mercado Pago", sent.first[:subject]
  end

  test "un fallo pasajero no cambia nada" do
    sent = capture_emails { TerminalConnections::Health.failed!(@connection, failure(:transient, "provider_unavailable")) }
    assert @connection.reload.connected?
    assert_empty sent
  end

  test "al recuperarse vuelve a poder avisar" do
    capture_emails { TerminalConnections::Health.failed!(@connection, failure) }
    TerminalConnections::Health.recovered!(@connection.reload)
    assert @connection.reload.connected?
    sent = capture_emails { TerminalConnections::Health.failed!(@connection, failure) }
    assert_not_empty sent
  end

  test "en una demo no sale ningún correo real" do
    Current.demo = true
    sent = capture_emails { TerminalConnections::Health.failed!(@connection, failure) }
    assert_empty sent
  ensure
    Current.demo = nil
  end
end
