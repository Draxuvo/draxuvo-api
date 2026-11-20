require "test_helper"

# Spec 069, research R2: renovación diaria de tokens.
class TerminalConnections::RefreshJobTest < ActiveJob::TestCase
  test "renueva las que vencen pronto y guarda el refresh token nuevo" do
    connection = terminal_connection_for(companies(:pro_co))
    connection.update!(token_expires_at: 10.days.from_now)
    fresh = terminal_connection_for(companies(:enterprise_co))
    with_fake_provider do |fake|
      fake.credentials = TerminalProviders::Credentials.new(access_token: "NEW", refresh_token: "TG-new", expires_at: 180.days.from_now)
      TerminalConnections::RefreshJob.perform_now
      assert_equal [ connection.id ], fake.calls_of(:refresh).map { |c| c[:connection_id] }
    end
    assert_equal "NEW", connection.reload.token
    assert_equal "TG-new", connection.renewal_token
    assert_equal "APP_USR-token", fresh.reload.token
  end

  test "si el proveedor rechaza la renovación la conexión queda con error" do
    connection = terminal_connection_for(companies(:pro_co))
    connection.update!(token_expires_at: 1.day.from_now)
    with_fake_provider do |fake|
      fake.refresh_error = provider_error(:connection, "unauthorized")
      Resend::Emails.stub(:send, ->(*) { resend_response }) { TerminalConnections::RefreshJob.perform_now }
    end
    assert connection.reload.error?
  end
end
