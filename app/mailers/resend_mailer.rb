class ResendMailer
  DEFAULT_SUBJECT = "Configura tu contraseña en Draxuvo"
  WELCOME_SUBJECT = "Bienvenido a Draxuvo"
  NOTICE_SUBJECTS = {
    "past_due" => "Tu pago de Draxuvo está pendiente",
    "suspended" => "Tu suscripción de Draxuvo está suspendida",
    "cancel_warning" => "Tu suscripción de Draxuvo se cancelará pronto"
  }.freeze

  class << self
    def set_password(user:, set_password_url:, company_name: nil)
      log(:warn, "#set_password START user_id=#{user&.id} email=#{user&.email} company=#{company_name.inspect}")
      validate_parameters(user, set_password_url)

      params = {
        from:    sender_email(company_name),
        to:      user.email,
        subject: "Bienvenido a #{company_name || "Draxuvo"} – Configura tu contraseña",
        html:    ApplicationController.render(
                   template: "resend_mailer/set_password",
                   layout:   false,
                   locals:   { user: user, set_password_url: set_password_url, company_name: company_name }
                 )
      }

      log(:warn, "#set_password params built from=#{params[:from].inspect} to=#{params[:to].inspect} subject=#{params[:subject].inspect}")
      send_email(params)
    rescue => e
      handle_email_error(user, e)
      false
    end

    def password_reset(user:, reset_url:, company_name: nil)
      log(:warn, "#password_reset START user_id=#{user&.id} email=#{user&.email} company=#{company_name.inspect}")
      validate_parameters(user, reset_url)

      email_params = build_email_params(user, reset_url, company_name)
      log(:warn, "#password_reset params built from=#{email_params[:from].inspect} to=#{email_params[:to].inspect}")
      send_email(email_params)
    rescue => e
      handle_email_error(user, e)
      false
    end

    def welcome(user:, company_name:, trial_ends_at:)
      log(:warn, "#welcome START user_id=#{user&.id} email=#{user&.email} company=#{company_name.inspect}")
      raise ArgumentError, "User parameter is required" unless user.present?
      raise ArgumentError, "User email is required" unless user.email.present?

      params = {
        from:    sender_email,
        to:      user.email,
        subject: WELCOME_SUBJECT,
        html:    ApplicationController.render(
                   template: "resend_mailer/welcome",
                   layout:   false,
                   locals:   { user: user, company_name: company_name, trial_ends_at: trial_ends_at }
                 )
      }

      log(:warn, "#welcome params built from=#{params[:from].inspect} to=#{params[:to].inspect}")
      send_email(params)
    rescue => e
      handle_email_error(user, e)
      false
    end

    # Avisos de suscripción (spec 031): pago pendiente, suspendida y cancelación próxima.
    def subscription_notice(user:, company_name:, kind:, plan: nil, pay_url: nil, grace_ends_at: nil, cancels_at: nil)
      raise ArgumentError, "User email is required" unless user&.email.present?

      send_email(
        from:    sender_email,
        to:      user.email,
        subject: NOTICE_SUBJECTS.fetch(kind),
        html:    ApplicationController.render(
                   template: "resend_mailer/subscription_notice",
                   layout:   false,
                   locals:   { user: user, company_name: company_name, kind: kind, plan: plan, pay_url: pay_url,
                               grace_ends_at: grace_ends_at, cancels_at: cancels_at }
                 )
      )
    rescue => e
      handle_email_error(user, e)
      false
    end

    # Aviso de stock bajo para dueño y administrador (spec 045): `kind` es "immediate" (productos que acaban de bajar)
    # o "daily" (resumen de todo lo que sigue bajo). Sin datos de clientes ni montos de cuentas (FR-025).
    def stock_alert(user:, company_name:, kind:, products:, locale: "es")
      raise ArgumentError, "User email is required" unless user&.email.present?

      locale = I18n.available_locales.map(&:to_s).include?(locale.to_s) ? locale.to_s : "es"
      send_email(
        from:    sender_email(company_name),
        to:      user.email,
        subject: I18n.t("alerts.email.#{kind}_subject", company: company_name, locale: locale),
        html:    ApplicationController.render(
                   template: "resend_mailer/stock_alert",
                   layout:   false,
                   locals:   { user: user, company_name: company_name, kind: kind, products: products, locale: locale }
                 )
      )
    rescue => e
      handle_email_error(user, e)
      false
    end

    private

    def validate_parameters(user, reset_url)
      raise ArgumentError, "User parameter is required" unless user.present?
      raise ArgumentError, "reset_url parameter is required" unless reset_url.present?
      raise ArgumentError, "User email is required" unless user.email.present?
    end

    def build_email_params(user, reset_url, company_name = nil)
      {
        from:    sender_email(company_name),
        to:      user.email,
        subject: DEFAULT_SUBJECT,
        html:    password_reset_html(user, reset_url, company_name)
      }
    end

    def password_reset_html(user, reset_url, company_name = nil)
      ApplicationController.render(
        template: "resend_mailer/password_reset",
        layout:   false,
        locals:   { user: user, reset_url: reset_url, company_name: company_name },
      )
    end

    # RESEND_FROM_EMAIL puede ser solo la dirección (`no-reply@draxuvo.com`) o con nombre
    # (`Draxuvo <no-reply@draxuvo.com>`). Con el nombre de la empresa se arma `Empresa <dirección>`;
    # envolver un valor que ya trae `<>` daba un remitente inválido y Resend rechazaba el correo.
    def sender_email(company_name = nil)
      configured = ENV["RESEND_FROM_EMAIL"].to_s.strip
      log(:warn, "#sender_email RESEND_FROM_EMAIL=#{configured.inspect} company_name=#{company_name.inspect}")
      address = configured[/<([^>]+)>/, 1] || configured
      name = company_name.to_s.delete('<>"').strip.presence
      name ? "#{name} <#{address}>" : configured
    end

    def send_email(params)
      # Spec 039: una demo no manda correos reales; tampoco a las direcciones reservadas de sus usuarios efímeros.
      if Demo::Guard.active? || params[:to].to_s.end_with?(".invalid")
        log(:info, "#send_email simulado (demo) to=#{params[:to].inspect}")
        return { "id" => "demo-simulated" }
      end

      api_key = ENV["RESEND_API_KEY"]
      log(:warn, "#send_email RESEND_API_KEY present=#{api_key.present?}")
      log(:warn, "#send_email calling Resend::Emails.send to=#{params[:to].inspect} from=#{params[:from].inspect}")

      response = Resend::Emails.send(params)

      log(:warn, "#send_email SUCCESS response=#{response.inspect}")
      response
    end

    def handle_email_error(user, error)
      error_details = {
        error:   error.class.name,
        message: error.message,
        user_id: user&.id,
        email:   user&.email,
        time:    Time.current.iso8601
      }
      log(:error, "handle_email_error #{error_details.to_json}")
      log(:error, "backtrace:\n#{error.backtrace&.first(5)&.join("\n")}")
      Sentry.capture_exception(error) if defined?(Sentry)
    end

    def log(level, msg)
      tagged = "[ResendMailer] #{msg}"
      Rails.logger.public_send(level, tagged)
      $stdout.puts tagged
      $stdout.flush
    end
  end
end
