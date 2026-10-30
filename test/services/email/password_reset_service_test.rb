require "test_helper"

class Email::PasswordResetServiceTest < ActiveSupport::TestCase
  def call_service(response, user: users(:pro_staff))
    captured = nil
    stub = ->(**args) { captured = args; response }
    result = with_env("FRONTEND_URL" => "https://app.test") do
      ResendMailer.stub(:password_reset, stub) do
        Email::PasswordResetService.new(user).call
      end
    end
    [ result, captured ]
  end

  test "sends a reset link with a signed token and the company name" do
    result, captured = call_service({ "id" => "email_1" })
    assert result[:success]
    assert_equal result[:reset_url], captured[:reset_url]
    assert_equal "Servicios Pro", captured[:company_name]
    assert result[:reset_url].start_with?("https://app.test/password?message=")
    token = CGI.unescape(result[:reset_url].split("message=").last)
    payload = JwtHelper.jwt_decode(token)
    assert_equal users(:pro_staff).id, payload[:user_id]
    assert_in_delta 24.hours.from_now.to_i, payload[:exp], 60
  end

  test "reports failure when the mailer returns false" do
    result, = call_service(false)
    assert_not result[:success]
    assert_includes result[:error], "Failed to send email"
  end

  test "rescues errors raised while sending" do
    with_env("FRONTEND_URL" => "https://app.test") do
      ResendMailer.stub(:password_reset, ->(**) { raise "boom" }) do
        assert_equal({ success: false, error: "boom" }, Email::PasswordResetService.new(users(:pro_staff)).call)
      end
    end
  end

  test "a real Resend response (HTTParty, symbol keys) counts as sent" do
    response = resend_response({ id: "01a18a23" })

    result = with_env("FRONTEND_URL" => "https://app.test") do
      Resend::Emails.stub(:send, ->(_params) { response }) do
        Email::PasswordResetService.new(users(:pro_staff)).call
      end
    end

    assert result[:success], result[:error]
  end

  test "validates the user on initialization" do
    assert_raises(ArgumentError) { Email::PasswordResetService.new(nil) }
    assert_raises(ArgumentError) { Email::PasswordResetService.new(User.new(email: "a@b.test")) }
    unsaved_email = users(:pro_staff).tap { |u| u.email = "" }
    assert_raises(ArgumentError) { Email::PasswordResetService.new(unsaved_email) }
  end
end
