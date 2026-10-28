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
          change_enabled if params.key?(:enabled)
          render_state(stale_kind: stale_kind(outcome))
        end

        # POST /api/v1/whatsapp/message_types/:kind/verify — «Verificar ahora» la plantilla del tipo.
        def verify
          reject_ticket!
          outcome = ::Whatsapp::TemplateVerification.call(@type, user: current_user)
          render_state(stale_kind: stale_kind(outcome))
        end

        # POST /api/v1/whatsapp/message_types/:kind/test — mensaje de prueba (5 por hora por super admin).
        def test
          phone = test_phone
          raise ApiErrors::TooManyRequestsError.new(message: I18n.t("whatsapp_admin.errors.tests_limit"), details: { code: "tests_limit" }) if ::Whatsapp::TestLimit.remaining(current_user).zero?

          result = ::Whatsapp::TestMessage.call(@type, phone: phone, user: current_user)
          masked = WhatsappEvent.mask_phone(phone)
          log_test(result, masked)
          raise_test_error(result) unless result.sent? || result.status == "simulated"

          render json: { result: result.status, to: masked, tests_remaining: ::Whatsapp::TestLimit.remaining(current_user) }
        end

        private

        # Solo dígitos, de 10 a 15; si no viene, el del perfil de quien prueba.
        def test_phone
          digits = (params[:phone].presence || current_user.phone).to_s.gsub(/\D/, "")
          return digits if digits.length.between?(10, 15)

          raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("whatsapp_admin.errors.invalid_phone"), details: { code: "invalid_phone" })
        end

        # Solo cuentan para el límite las pruebas que llegaron a Meta (enviadas o rechazadas).
        def log_test(result, masked)
          return unless %w[sent failed].include?(result.status)

          WhatsappEvent.log!(action: "test_sent", target: @type.kind, user: current_user, result: result.sent? ? "ok" : "failed",
                             meta_code: result.meta_code, data: { to: masked, reason: result.reason }.compact)
        end

        def raise_test_error(result)
          case result.status
          when "unreachable"
            raise ApiErrors::ServiceUnavailableError.new(message: I18n.t("whatsapp_admin.reasons.meta_unreachable"), details: { code: "meta_unreachable" })
          when "blocked"
            raise ApiErrors::UnprocessableEntityError.new(
              message: I18n.t("whatsapp_admin.errors.#{result.reason}"), details: { code: result.reason, template_status: result.template_status }.compact
            )
          else
            raise ApiErrors::UnprocessableEntityError.new(
              message: I18n.t("whatsapp_admin.reasons.#{result.reason}", default: I18n.t("whatsapp_admin.reasons.unknown")),
              details: { code: "test_failed", reason: result.reason, meta_code: result.meta_code&.to_s }
            )
          end
        end

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

        # Apagar siempre se puede; encender exige conexión válida y, si usa plantilla, plantilla aprobada y compatible.
        def change_enabled
          enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
          return if enabled == @type.enabled?

          if enabled && (reason = @type.blocked_reason)
            raise ApiErrors::UnprocessableEntityError.new(
              message: I18n.t("whatsapp_admin.errors.#{reason}"), details: { code: reason, template_status: @type.template_status }
            )
          end

          @type.update!(enabled: enabled, problem_notified_at: enabled ? nil : @type.problem_notified_at)
          WhatsappEvent.log!(action: enabled ? "type_on" : "type_off", target: @type.kind, user: current_user,
                             data: { from: !enabled, to: enabled })
        end

        # Meta no respondió (o no hay conexión): se conserva el último estado conocido y se avisa con `stale: true`.
        def stale_kind(outcome) = outcome&.stale? ? @type.kind : nil
      end
    end
  end
end
