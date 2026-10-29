require "test_helper"

# Spec 047, FR-019a: el correo al equipo dice qué falló y desde cuándo, sin la llave ni números completos.
class WhatsappAlertMailerTest < ActiveSupport::TestCase
  setup { @user = users(:super_admin) }

  def send_mail(problem: "connection", target: "connection", detail: "La llave venció; genera una nueva en Meta", locale: "es")
    sent = nil
    Resend::Emails.stub(:send, ->(params) { sent = params; { "id" => "email_1" } }) do
      with_env("RESEND_FROM_EMAIL" => "Draxuvo <no-reply@draxuvo.com>", "FRONTEND_URL" => "https://app.draxuvo.com/") do
        ResendMailer.whatsapp_alert(user: @user, problem: problem, target: target, detail: detail, since: Time.utc(2026, 10, 28, 17, 30), locale: locale)
      end
    end
    sent
  end

  test "a connection problem says what failed, since when, and links to the WhatsApp page" do
    sent = send_mail

    assert_equal "WhatsApp necesita atención en Draxuvo", sent[:subject]
    assert_equal @user.email, sent[:to]
    assert_equal "Draxuvo <no-reply@draxuvo.com>", sent[:from]
    assert_includes sent[:html], "La conexión de WhatsApp falló (La llave venció; genera una nueva en Meta)."
    assert_includes sent[:html], "28/10/2026 11:30"
    assert_includes sent[:html], "https://app.draxuvo.com/es/whatsapp"
  end

  test "a template problem names the type that was turned off" do
    sent = send_mail(problem: "template", target: "verification_code", detail: "La plantilla no existe en ese idioma o no está aprobada")

    assert_includes sent[:html], "Se apagó los códigos de verificación porque su plantilla ya no sirve"
    assert_includes sent[:html], "La plantilla no existe en ese idioma o no está aprobada"
  end

  test "English is supported" do
    sent = send_mail(locale: "en", detail: "The key expired")

    assert_equal "WhatsApp needs attention in Draxuvo", sent[:subject]
    assert_includes sent[:html], "The WhatsApp connection failed (The key expired)."
    assert_includes sent[:html], "https://app.draxuvo.com/en/whatsapp"
  end

  test "an unknown language falls back to Spanish" do
    sent = send_mail(locale: "fr")
    assert_equal "WhatsApp necesita atención en Draxuvo", sent[:subject]
  end

  test "it carries no key and no full phone number" do
    html = send_mail(detail: "La llave venció")[:html]

    assert_no_match(/EAAG/, html)
    assert_no_match(/\d{10,}/, html)
  end

  test "a failure to send is reported as false and never raised" do
    result = Resend::Emails.stub(:send, ->(*) { raise "boom" }) do
      ResendMailer.whatsapp_alert(user: @user, problem: "connection", target: "connection", detail: "x", since: Time.current)
    end
    assert_equal false, result
  end

  test "in a demo the email is simulated" do
    Current.demo = true
    result = ResendMailer.whatsapp_alert(user: @user, problem: "connection", target: "connection", detail: "x", since: Time.current)
    assert_equal "demo-simulated", result["id"]
  ensure
    Current.reset
  end
end
