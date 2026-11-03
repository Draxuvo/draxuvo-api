module Subscriptions
  # Aviso por correo a dueños y administradores cuando el super admin enciende o apaga un módulo extra (spec 053, FR-030).
  # Una demo nunca manda correos; un fallo del correo no revierte el cambio.
  class AddonNoticeService
    def initialize(company:, addon:, action:, effective_on: nil)
      @company = company
      @addon = addon
      @action = action.to_s
      @effective_on = effective_on
    end

    def call
      return false if @company.demo?

      subscription = @company.billing_subscription
      recipients.each do |user|
        ResendMailer.addon_changed(
          user: user, company_name: @company.name, module_name: I18n.t("modules.#{@addon.key}", locale: :es),
          action: @action, effective_on: @effective_on, total_cents: subscription&.total_cents
        )
      end
      true
    rescue StandardError => e
      Rails.logger.error("[Subscriptions::AddonNoticeService] #{e.class}: #{e.message}")
      false
    end

    private

    def recipients
      @company.user_companies.where(role: %i[owner admin]).includes(:user).map(&:user).compact.select(&:active?).uniq
    end
  end
end
