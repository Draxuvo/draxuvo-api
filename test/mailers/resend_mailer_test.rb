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

  # --- spec 031: avisos de suscripción ---

  test "the subscription notices go to Resend with their subject, the plan and the pay button" do
    sent = []
    Resend::Emails.stub(:send, ->(params) { sent << params; { "id" => "email_1" } }) do
      %w[past_due suspended cancel_warning].each do |kind|
        ResendMailer.subscription_notice(user: users(:pro_co_owner), company_name: "Volta", kind: kind, plan: "pro",
                                         pay_url: "https://invoice.stripe.com/i/x", grace_ends_at: 7.days.from_now,
                                         cancels_at: 30.days.from_now)
      end
    end

    assert_equal ResendMailer::NOTICE_SUBJECTS.values, sent.map { |mail| mail[:subject] }
    assert sent.all? { |mail| mail[:html].include?("https://invoice.stripe.com/i/x") && mail[:html].include?("Pagar ahora") }
    assert_includes sent[1][:html], "plan pro"
  end

  # --- respuesta real de la gema `resend` ---

  test "a real Resend response comes back as a plain Hash with string keys" do
    result = Resend::Emails.stub(:send, ->(_params) { resend_response }) do
      ResendMailer.password_reset(user: users(:pro_staff), reset_url: "https://app.test/r?token=x", company_name: "Mi Empresa")
    end

    assert_instance_of Hash, result
    assert_equal "email_1", result["id"]
  end

  test "the other mails also return the normalized response" do
    result = Resend::Emails.stub(:send, ->(_params) { resend_response }) do
      ResendMailer.set_password(user: users(:pro_staff), set_password_url: "https://app.test/s?token=x", company_name: "Mi Empresa")
    end

    assert_equal "email_1", result["id"]
  end

  # --- correo en Gmail y Outlook: sin degradados ni rgba, el texto blanco quedaba sobre blanco ---

  test "every gradient in the mail templates has a solid color as a fallback" do
    Dir[Rails.root.join("app/views/resend_mailer/*.erb")].each do |path|
      File.read(path).scan(/style="([^"]*linear-gradient[^"]*)"/m).flatten.each do |style|
        assert_match(/background-color:\s*#[0-9a-fA-F]{3,6}/, style, "#{File.basename(path)}: degradado sin color sólido de respaldo")
      end
    end
  end

  test "the white circle behind the logo initial has a solid color too" do
    Dir[Rails.root.join("app/views/resend_mailer/*.erb")].each do |path|
      File.read(path).scan(/style="([^"]*background:\s*rgba[^"]*)"/m).flatten.each do |style|
        flunk "#{File.basename(path)}: fondo rgba() sin color sólido: #{style.squish}"
      end
    end
  end
end
