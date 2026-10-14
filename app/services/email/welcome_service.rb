# Correo de bienvenida del registro público (FR-015) con la fecha de fin de la prueba.
module Email
  class WelcomeService
    def initialize(user, company_name:, trial_ends_at:)
      @user = user
      @company_name = company_name
      @trial_ends_at = trial_ends_at
    end

    def call
      response = ResendMailer.welcome(user: @user, company_name: @company_name, trial_ends_at: @trial_ends_at)

      if email_sent_successfully?(response)
        Rails.logger.info "[Welcome] Email sent to #{@user.email}"
        { success: true }
      else
        error_message = "Failed to send email. Response: #{response.inspect}"
        Rails.logger.error "[Welcome] #{error_message}"
        { success: false, error: error_message }
      end
    rescue => e
      Rails.logger.error "[Welcome] Error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
      { success: false, error: e.message }
    end

    private

    def email_sent_successfully?(response)
      response.is_a?(Hash) && response["id"].present?
    end
  end
end
