require "test_helper"

class Email::SetPasswordServiceTest < ActiveSupport::TestCase
  def call_service(response, company_name: "Servicios Pro")
    captured = nil
    stub = ->(**args) { captured = args; response }
    result = with_env("FRONTEND_URL" => "https://app.test") do
      ResendMailer.stub(:set_password, stub) do
        Email::SetPasswordService.new(users(:pro_staff), company_name: company_name).call
      end
    end
    [ result, captured ]
  end

  test "sends a link with a signed token" do
    result, captured = call_service({ "id" => "email_1" })
    assert_equal({ success: true }, result)
    assert_equal "Servicios Pro", captured[:company_name]
    url = captured[:set_password_url]
    assert url.start_with?("https://app.test/set-password?token=")
    token = CGI.unescape(url.split("token=").last)
    payload = JwtHelper.jwt_decode(token)
    assert_equal users(:pro_staff).id, payload[:user_id]
    assert_equal users(:pro_staff).email, payload[:email]
    # El :exp del payload se respeta: el enlace de alta dura 72 h (TOKEN_EXPIRATION), no las 24 h por omisión.
    assert_in_delta Email::SetPasswordService::TOKEN_EXPIRATION.from_now.to_i, payload[:exp], 60
  end

  test "defaults to the local frontend url" do
    captured = nil
    with_env("FRONTEND_URL" => nil) do
      ResendMailer.stub(:set_password, ->(**args) { captured = args; { "id" => "x" } }) do
        Email::SetPasswordService.new(users(:pro_staff)).call
      end
    end
    assert captured[:set_password_url].start_with?("http://localhost:4200/set-password?token=")
    assert_nil captured[:company_name]
  end

  test "reports failure when the mailer swallows an error and returns false" do
    result, = call_service(false)
    assert_not result[:success]
    assert_includes result[:error], "Failed to send email"
  end

  test "rescues errors raised while sending" do
    with_env("FRONTEND_URL" => "https://app.test") do
      ResendMailer.stub(:set_password, ->(**) { raise "boom" }) do
        assert_equal({ success: false, error: "boom" }, Email::SetPasswordService.new(users(:pro_staff)).call)
      end
    end
  end
end
