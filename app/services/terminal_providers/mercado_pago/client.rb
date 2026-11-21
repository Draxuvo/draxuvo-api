require "net/http"
require "json"

module TerminalProviders
  class MercadoPago
    # Única salida de Draxuvo hacia la API de Mercado Pago (spec 069, research R1 y R10). Clasifica cada error en una
    # familia de `TerminalProviders::Failure`; nunca registra el token ni el cuerpo con datos de la cuenta.
    class Client
      BASE = "https://api.mercadopago.com".freeze
      OPEN_TIMEOUT = 3
      READ_TIMEOUT = 8

      # Respuesta ya interpretada: código HTTP y cuerpo JSON (Hash vacío si no hay).
      Response = Struct.new(:status, :body, keyword_init: true)

      def initialize(token: nil)
        @token = token
      end

      def get(path, query: {}) = request(Net::HTTP::Get, path, query: query)

      def post(path, body: nil, idempotency_key: nil, headers: {}, auth: true)
        request(Net::HTTP::Post, path, body: body, idempotency_key: idempotency_key, headers: headers, auth: auth)
      end

      def patch(path, body:) = request(Net::HTTP::Patch, path, body: body)

      private

      def request(klass, path, query: {}, body: nil, idempotency_key: nil, headers: {}, auth: true)
        uri = URI.join(BASE, path)
        uri.query = URI.encode_www_form(query) if query.present?
        req = klass.new(uri)
        req["Content-Type"] = "application/json"
        req["Accept"] = "application/json"
        req["Authorization"] = "Bearer #{@token}" if auth && @token
        req["X-Idempotency-Key"] = idempotency_key if idempotency_key
        headers.each { |key, value| req[key] = value }
        req.body = JSON.generate(body) unless body.nil?

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        response = http.request(req)
        parsed = parse(response.body)
        status = response.code.to_i
        return Response.new(status: status, body: parsed) if status.between?(200, 299)

        raise_failure(status, parsed, path)
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, OpenSSL::SSL::SSLError, EOFError
        raise TerminalProviders::Error.new(TerminalProviders::Failure.new(family: :transient, reason: "provider_unavailable"))
      end

      def parse(raw)
        raw.present? ? JSON.parse(raw) : {}
      rescue JSON::ParserError
        {}
      end

      # Mercado Pago responde errores como { error, message, status } o { errors: [{ code, message }] }.
      def raise_failure(status, body, path)
        code = error_code(body)
        family =
          if [ 401, 403 ].include?(status) then :connection
          elsif status == 404 && path.start_with?("/terminals") then :device
          elsif status == 404 then :other
          elsif status == 409 then :conflict
          elsif [ 425, 429 ].include?(status) || status >= 500 then :transient
          elsif [ 400, 422, 428 ].include?(status) then :declined
          else :other
          end
        Rails.logger.warn("[terminal:mercado_pago] #{status} #{code} #{path.split('?').first}")
        raise TerminalProviders::Error.new(TerminalProviders::Failure.new(family: family, reason: code, http_status: status))
      end

      def error_code(body)
        first = Array(body["errors"]).first
        code = (first.is_a?(Hash) && (first["code"] || first["error"])) || body["error"] || body["code"] || "error"
        code.to_s.downcase.gsub(/[^a-z0-9_]/, "_").first(60)
      end
    end
  end
end
