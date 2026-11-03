# Errores comunes de los servicios de venta (spec 050): 422 con `details.code` y el mensaje traducido.
module Sales
  module Failures
    private

    def fail!(code, status: :unprocessable_entity, **details)
      raise ApiErrors::BaseError.new(
        status: status, message: I18n.t("sale.errors.#{code}", default: I18n.t("errors.unprocessable")), details: { code: code.to_s, **details }
      )
    end

    def not_found!(code = :product_not_found)
      raise ApiErrors::NotFoundError.new(message: I18n.t("sale.errors.#{code}"), details: { code: code.to_s })
    end

    def ensure_open!(sale)
      fail!(:not_open) unless sale.status_open?
    end

    def decimal(value)
      return nil if value.to_s.strip.empty?

      BigDecimal(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
