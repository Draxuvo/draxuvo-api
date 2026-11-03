require "test_helper"

# Spec 053, FR-030: el aviso lleva el módulo, la fecha efectiva y el nuevo total.
class AddonChangedMailerTest < ActiveSupport::TestCase
  def send_mail(action:, effective_on: nil)
    sent = nil
    Resend::Emails.stub(:send, ->(params) { sent = params; { "id" => "email_1" } }) do
      with_env("RESEND_FROM_EMAIL" => "Draxuvo <no-reply@draxuvo.com>", "FRONTEND_URL" => "https://app.draxuvo.com/") do
        ResendMailer.addon_changed(user: users(:basic_co_owner), company_name: "Taller Básico", module_name: "Punto de venta",
                                   action: action, effective_on: effective_on, total_cents: 69_368)
      end
    end
    sent
  end

  test "turning it on says the module and the new total" do
    sent = send_mail(action: "on")
    assert_equal "Se activó Punto de venta en tu empresa", sent[:subject]
    assert_includes sent[:html], "$693.68"
    assert_includes sent[:html], "https://app.draxuvo.com/es/suscripcion"
  end

  test "turning it off says until when it stays" do
    sent = send_mail(action: "off", effective_on: Time.zone.local(2026, 12, 15))
    assert_equal "Se desactivará Punto de venta en tu empresa", sent[:subject]
    assert_includes sent[:html], "15 de diciembre de 2026"
  end

  test "the notice goes to owners and active administrators, never in a demo" do
    company = companies(:basic_co)
    admin = create_member(company, role: :admin)
    sent_to = []
    ResendMailer.stub(:addon_changed, ->(user:, **) { sent_to << user }) do
      Subscriptions::AddonNoticeService.new(company: company, addon: Addon.find(:pos), action: "on").call
      assert_includes sent_to, users(:basic_co_owner)
      assert_includes sent_to, admin
      assert_not_includes sent_to, create_member(company, role: :staff)

      sent_to.clear
      company.update_columns(demo: true)
      assert_not Subscriptions::AddonNoticeService.new(company: company, addon: Addon.find(:pos), action: "on").call
      assert_empty sent_to
    end
  end
end
