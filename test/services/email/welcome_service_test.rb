require "test_helper"

class Email::WelcomeServiceTest < ActiveSupport::TestCase
  def call_service(response)
    captured = nil
    stub = ->(**args) { captured = args; response }
    result = ResendMailer.stub(:welcome, stub) do
      Email::WelcomeService.new(users(:pro_staff), company_name: "Servicios Pro", trial_ends_at: 30.days.from_now).call
    end
    [ result, captured ]
  end

  test "sends the welcome email and reports success" do
    result, captured = call_service({ "id" => "email_1" })
    assert_equal({ success: true }, result)
    assert_equal users(:pro_staff), captured[:user]
    assert_equal "Servicios Pro", captured[:company_name]
    assert_not_nil captured[:trial_ends_at]
  end

  test "reports failure when the mailer returns false" do
    result, = call_service(false)
    assert_not result[:success]
    assert_includes result[:error], "Failed to send email"
  end

  test "reports failure when the response has no id" do
    result, = call_service({ "id" => "" })
    assert_not result[:success]
  end

  test "rescues errors raised by the mailer" do
    ResendMailer.stub(:welcome, ->(**) { raise "Resend caído" }) do
      result = Email::WelcomeService.new(users(:pro_staff), company_name: "X", trial_ends_at: nil).call
      assert_equal({ success: false, error: "Resend caído" }, result)
    end
  end
end
