module TerminalCharges
  # Errores de la API para las solicitudes de cobro (spec 069, contracts/api.md).
  module Errors
    module_function

    def invalid!(code, **details)
      raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("terminal_charge.errors.#{code}"), details: { code: code.to_s, **details })
    end

    def conflict!(code, **details)
      raise ApiErrors::BaseError.new(status: :conflict, message: I18n.t("terminal_charge.errors.#{code}"), details: { code: code.to_s, **details })
    end

    def bad_gateway!(code)
      raise ApiErrors::BaseError.new(status: 502, message: I18n.t("terminal_charge.errors.#{code}"), details: { code: code.to_s })
    end
  end
end
