require "test_helper"

# Spec 039, FR-006 y FR-007: la barrera que impide que una demo mande correos, mensajes o cobros reales.
class Demo::GuardTest < ActiveSupport::TestCase
  test "active? follows Current.demo and restrict! raises only in a demo" do
    assert_not Demo::Guard.active?
    assert_nil Demo::Guard.restrict!(:payment)

    as_demo do
      assert Demo::Guard.active?
      error = assert_raises(Demo::Restricted) { Demo::Guard.restrict!(:plan_change) }
      assert_equal :plan_change, error.action
    end
  end

  test "Current.demo does not leak between blocks" do
    as_demo { assert Demo::Guard.active? }

    assert_not Demo::Guard.active?
  end

  test "ResendMailer sends nothing in a demo and does send outside it" do
    user = users(:pro_co_owner)
    calls = []
    fake = ->(params) { calls << params && { "id" => "real" } }

    Resend::Emails.stub(:send, fake) do
      as_demo { ResendMailer.welcome(user: user, company_name: "Demo", trial_ends_at: 30.days.from_now) }
      assert_empty calls, "una demo no debe enviar correos"

      ResendMailer.welcome(user: user, company_name: "Real", trial_ends_at: 30.days.from_now)
      assert_equal 1, calls.size
    end
  end

  test "ResendMailer set_password and password_reset are silent in a demo too" do
    user = users(:pro_co_owner)
    Resend::Emails.stub(:send, ->(_params) { flunk "se llamó a Resend desde una demo" }) do
      as_demo do
        assert ResendMailer.set_password(user: user, set_password_url: "https://x.test/p", company_name: "Demo")
        assert ResendMailer.password_reset(user: user, reset_url: "https://x.test/r", company_name: "Demo")
      end
    end
  end

  test "ResendMailer also skips addresses on the reserved .invalid domain" do
    ephemeral = User.new(first_name: "Demo", email: "demo-abc@demo.invalid")
    Resend::Emails.stub(:send, ->(_params) { flunk "se intentó enviar a un dominio inválido" }) do
      assert ResendMailer.password_reset(user: ephemeral, reset_url: "https://x.test/r")
    end
  end

  test "the WhatsApp ticket service does not reach Graph in a demo" do
    ticket = tickets(:one) if respond_to?(:tickets)
    ticket ||= Ticket.first
    Net::HTTP.stub(:start, ->(*) { flunk "se llamó a la API de WhatsApp desde una demo" }) do
      result = as_demo { Whatsapp::TicketService.new(ticket, phone: "5512345678").call }

      assert_equal({ "demo" => true }, result)
    end
  end

  test "the WhatsApp OTP service sends no code in a demo but keeps verification working" do
    Net::HTTP.stub(:start, ->(*) { flunk "se llamó a la API de WhatsApp desde una demo" }) do
      Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
        code = as_demo { Whatsapp::OtpService.new("5512345678").send_code }

        assert_equal Demo::Guard::DEMO_OTP, code
        assert Whatsapp::OtpService.new("5512345678").verify(code)[:verified]
      end
    end
  end

  test "the Stripe services refuse in a demo with the action" do
    company = companies(:pro_co)
    as_demo do
      checkout = Subscriptions::CreateCheckoutService.new(company: company, plan: "pro", success_url: "x", cancel_url: "y")
      assert_equal :payment, assert_raises(Demo::Restricted) { checkout.call }.action
      portal = Subscriptions::PortalService.new(company: company, return_url: "x")
      assert_equal :payment, assert_raises(Demo::Restricted) { portal.call }.action
    end
  end
end
