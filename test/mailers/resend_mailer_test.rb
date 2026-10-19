require "test_helper"

# El mailer siempre se simula en las demás pruebas; aquí se comprueba el remitente que llega a Resend.
class ResendMailerTest < ActiveSupport::TestCase
  def sent_from(from_email:, company_name:)
    captured = nil
    Resend::Emails.stub(:send, ->(params) { captured = params; { "id" => "email_1" } }) do
      with_env("RESEND_FROM_EMAIL" => from_email) do
        ResendMailer.set_password(user: users(:pro_staff), set_password_url: "https://app.test/set-password?token=x", company_name: company_name)
      end
    end
    captured[:from]
  end

  test "a sender with a name keeps one single address when the company name is added" do
    assert_equal "Mi Empresa <no-reply@draxuvo.com>", sent_from(from_email: "Draxuvo <no-reply@draxuvo.com>", company_name: "Mi Empresa")
  end

  test "a bare address gets the company name" do
    assert_equal "Mi Empresa <no-reply@draxuvo.com>", sent_from(from_email: "no-reply@draxuvo.com", company_name: "Mi Empresa")
  end

  test "without a company name the configured sender goes as is" do
    assert_equal "Draxuvo <no-reply@draxuvo.com>", sent_from(from_email: "Draxuvo <no-reply@draxuvo.com>", company_name: nil)
    assert_equal "no-reply@draxuvo.com", sent_from(from_email: "no-reply@draxuvo.com", company_name: nil)
  end

  test "characters that break the header are dropped from the company name" do
    assert_equal "Taco Bar <no-reply@draxuvo.com>", sent_from(from_email: "Draxuvo <no-reply@draxuvo.com>", company_name: 'Taco "<Bar>"')
  end

  test "the password reset uses the same sender rule" do
    captured = nil
    Resend::Emails.stub(:send, ->(params) { captured = params; { "id" => "e" } }) do
      with_env("RESEND_FROM_EMAIL" => "Draxuvo <no-reply@draxuvo.com>") do
        ResendMailer.password_reset(user: users(:pro_staff), reset_url: "https://app.test/r?token=x", company_name: "Mi Empresa")
      end
    end
    assert_equal "Mi Empresa <no-reply@draxuvo.com>", captured[:from]
  end
end
