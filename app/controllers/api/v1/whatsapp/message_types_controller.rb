# Contrato: specs/047-configurar-whatsapp/contracts/api.md (/whatsapp/message_types). Siempre `::Whatsapp::` dentro de
# `Api::V1`, para que el módulo de servicios no quede sombreado por este espacio de nombres.
module Api
  module V1
    module Whatsapp
      class MessageTypesController < BaseController
        include WhatsappAccess

        before_action :set_type

        # PATCH /api/v1/whatsapp/message_types/:kind — cambiar la plantilla la verifica de inmediato y apaga el tipo.
        def update
          @type.lock_version = params[:lock_version] if params[:lock_version].present?
          outcome = change_template if template_params?
          render_state(stale_kind: stale_kind(outcome))
        end

        # POST /api/v1/whatsapp/message_types/:kind/verify — «Verificar ahora» la plantilla del tipo.
        def verify
          reject_ticket!
          outcome = ::Whatsapp::TemplateVerification.call(@type, user: current_user)
          render_state(stale_kind: stale_kind(outcome))
        end

        private

        def set_type
          raise ActiveRecord::RecordNotFound unless WhatsappMessageType::KINDS.include?(params[:kind])

          @type = WhatsappMessageType.ensure_all!.find_by!(kind: params[:kind])
        end

        def template_params?
          params.key?(:template_name) || params.key?(:template_language)
        end

        def reject_ticket!
          return if @type.uses_template?

          raise ApiErrors::UnprocessableEntityError.new(
            message: I18n.t("whatsapp_admin.errors.ticket_has_no_template"), details: { code: "ticket_has_no_template" }
          )
        end

        def change_template
          reject_ticket!
          name = params.key?(:template_name) ? params[:template_name].to_s.strip : @type.template_name.to_s
          language = params[:template_language].presence || @type.template_language
          return if name == @type.template_name.to_s && language == @type.template_language

          was_enabled = @type.enabled?
          from = { name: @type.template_name, language: @type.template_language }
          @type.update!(template_name: name, template_language: language, template_status: "unknown", template_detail: nil,
                        template_checked_at: nil, enabled: false, problem_notified_at: nil)
          WhatsappEvent.log!(action: "template_changed", target: @type.kind, user: current_user,
                             data: { from: from, to: { name: name, language: language } })
          WhatsappEvent.log!(action: "type_off", target: @type.kind, user: current_user, data: { from: true, to: false }) if was_enabled
          ::Whatsapp::TemplateVerification.call(@type, user: current_user)
        end

        # Meta no respondió (o no hay conexión): se conserva el último estado conocido y se avisa con `stale: true`.
        def stale_kind(outcome) = outcome&.stale? ? @type.kind : nil
      end
    end
  end
end
