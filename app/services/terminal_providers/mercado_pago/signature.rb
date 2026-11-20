require "openssl"

module TerminalProviders
  class MercadoPago
    # Valida la firma de un aviso de Mercado Pago (spec 069, research R4): encabezado `x-signature: ts=<ts>,v1=<hmac>` y
    # `x-request-id`, con HMAC-SHA256 del secreto de Webhooks sobre `id:<data.id>;request-id:<x-request-id>;ts:<ts>;`.
    # La plantilla es la de los SDK oficiales; queda por comprobar con un aviso real (tarea T080).
    module Signature
      MAX_SKEW = 10.minutes

      module_function

      # Devuelve true o lanza TerminalProviders::InvalidSignature.
      def verify!(signature:, request_id:, data_id:, secret: ENV["MERCADO_PAGO_WEBHOOK_SECRET"], now: Time.current)
        raise InvalidSignature, "missing_secret" if secret.blank?

        parts = parse(signature)
        ts = parts["ts"]
        v1 = parts["v1"]
        raise InvalidSignature, "malformed" if ts.blank? || v1.blank?
        raise InvalidSignature, "stale" if (now.to_i - timestamp_seconds(ts)).abs > MAX_SKEW.to_i

        expected = OpenSSL::HMAC.hexdigest("SHA256", secret, manifest(data_id: data_id, request_id: request_id, ts: ts))
        raise InvalidSignature, "mismatch" unless ActiveSupport::SecurityUtils.secure_compare(expected, v1.downcase)

        true
      end

      # Arma el texto firmado; las partes ausentes se omiten, como hacen los SDK.
      def manifest(data_id:, request_id:, ts:)
        text = +""
        text << "id:#{normalize_id(data_id)};" if data_id.present?
        text << "request-id:#{request_id};" if request_id.present?
        text << "ts:#{ts};"
        text
      end

      # Un `data.id` alfanumérico va en minúsculas.
      def normalize_id(data_id)
        value = data_id.to_s
        value.match?(/\A\d+\z/) ? value : value.downcase
      end

      def parse(signature)
        signature.to_s.split(",").each_with_object({}) do |pair, out|
          key, value = pair.split("=", 2).map { |part| part.to_s.strip }
          out[key] = value if key.present?
        end
      end

      # Mercado Pago manda segundos; si llegara en milisegundos se convierte.
      def timestamp_seconds(ts)
        value = ts.to_i
        value > 10_000_000_000 ? value / 1000 : value
      end
    end
  end
end
