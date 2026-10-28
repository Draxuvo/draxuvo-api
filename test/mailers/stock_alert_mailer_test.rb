require "test_helper"

# Spec 045, FR-025: el correo lleva la empresa y un enlace al inventario, y nada de clientes ni montos.
class StockAlertMailerTest < ActiveSupport::TestCase
  setup do
    @user = users(:pro_staff)
    @products = [ products(:resto_cola), products(:resto_tacos) ]
  end

  def send_mail(kind: "immediate", locale: "es")
    sent = nil
    Resend::Emails.stub(:send, ->(params) { sent = params; { "id" => "email_1" } }) do
      with_env("RESEND_FROM_EMAIL" => "Draxuvo <no-reply@draxuvo.com>", "FRONTEND_URL" => "https://app.draxuvo.com/") do
        ResendMailer.stock_alert(user: @user, company_name: "Café Aroma", kind: kind, products: @products, locale: locale)
      end
    end
    sent
  end

  test "an immediate notice lists the products with stock and minimum and links to the inventory" do
    sent = send_mail

    assert_equal "Stock bajo en Café Aroma", sent[:subject]
    assert_equal "Café Aroma <no-reply@draxuvo.com>", sent[:from]
    assert_equal @user.email, sent[:to]
    assert_includes sent[:html], "Refresco de cola"
    assert_includes sent[:html], "Tacos al pastor"
    assert_includes sent[:html], "https://app.draxuvo.com/es/inventario"
    assert_includes sent[:html], "llegaron a su mínimo"
  end

  test "the daily summary has its own subject and wording" do
    sent = send_mail(kind: "daily")
    assert_equal "Resumen de stock bajo · Café Aroma", sent[:subject]
    assert_includes sent[:html], "siguen en o bajo su mínimo"
  end

  test "English is supported for when people have a language" do
    sent = send_mail(locale: "en")
    assert_equal "Low stock at Café Aroma", sent[:subject]
    assert_includes sent[:html], "reached their minimum"
    assert_includes sent[:html], "https://app.draxuvo.com/en/inventario"
  end

  test "an unknown language falls back to Spanish in the body" do
    sent = send_mail(locale: "fr")
    assert_includes sent[:html], "llegaron a su mínimo"
  end

  test "it carries no customer data or amounts" do
    html = send_mail[:html]
    assert_no_match(/\$\s?\d/, html)
    assert_no_match(/Luis|Ana López|cliente/i, html)
  end

  test "a failure to send is reported as false and never raised" do
    result = Resend::Emails.stub(:send, ->(*) { raise "boom" }) { ResendMailer.stock_alert(user: @user, company_name: "X", kind: "daily", products: @products) }
    assert_equal false, result
  end

  test "in a demo the email is simulated" do
    Current.demo = true
    result = ResendMailer.stock_alert(user: @user, company_name: "Demo", kind: "immediate", products: @products)
    assert_equal "demo-simulated", result["id"]
  ensure
    Current.reset
  end
end
