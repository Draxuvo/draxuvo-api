require "net/http"
require "json"

module Whatsapp
  # Única salida de Draxuvo hacia la API de Meta (spec 047): reemplaza las tres copias del código de petición de los
  # servicios de WhatsApp y clasifica cada error de Meta en una familia para que `Whatsapp::Health` sepa qué hacer:
  #
  #   connection  la llave, la cuenta o el número fallan  → la conexión pasa a «Con error»
  #   template    la plantilla no existe, no coincide o está pausada → ese tipo de mensaje se apaga
  #   recipient   el destinatario no puede recibirlo       → no cambia ningún estado
  #   transient   límite de envío, Meta caído o sin red     → no cambia ningún estado
  #   other       cualquier otro rechazo                    → lo interpreta quien llama (p. ej. la verificación)
  #
  # Códigos tomados de la documentación de Meta (research.md, T002). La llave nunca se registra ni se devuelve.
  class GraphClient
    API_VERSION = "v25.0"
    BASE = "https://graph.facebook.com".freeze
    OPEN_TIMEOUT = 3
    READ_TIMEOUT = 5

    Failure = Struct.new(:family, :reason, :code, :subcode, :message, :http_status, keyword_init: true) do
      def connection? = family == :connection
      def template? = family == :template
      def transient? = family == :transient

      # Texto para quien llamó: el mensaje de Meta, uno genérico con el HTTP si no trae mensaje, o «no se pudo contactar a
      # Meta» cuando ni siquiera hubo respuesta (red, tiempo agotado).
      def user_message
        return I18n.t("whatsapp_admin.reasons.#{reason}", default: I18n.t("whatsapp_admin.reasons.unknown")) if http_status.nil?

        message.presence || "WhatsApp API error (HTTP #{http_status})"
      end
    end

    Result = Struct.new(:data, :failure, keyword_init: true) do
      def ok? = failure.nil?
    end

    CONNECTION_CODES = {
      10 => "missing_permission", 102 => "invalid_token", 200 => "invalid_token", 368 => "account_restricted",
      131_031 => "account_restricted", 133_010 => "invalid_number"
    }.freeze
    TEMPLATE_CODES = {
      132_001 => "template_missing", 132_000 => "template_variables", 132_012 => "template_variables",
      132_015 => "template_paused", 132_016 => "template_paused"
    }.freeze
    RECIPIENT_CODES = {
      131_026 => "recipient_invalid", 131_021 => "recipient_invalid", 131_047 => "outside_24h_window",
      131_030 => "not_authorized_recipient"
    }.freeze
    TRANSIENT_CODES = [ 130_429, 131_048, 80_007, 4, 17, 32, 613 ].freeze
    # Subcódigo de 190: 463 = la llave venció; cualquier otro = no es válida.
    EXPIRED_SUBCODE = 463
    NETWORK_ERRORS = [ Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError ].freeze

    def initialize(token:, read_timeout: READ_TIMEOUT)
      @token = token.to_s
      @read_timeout = read_timeout
    end

    def get(path, query = {})
      perform(Net::HTTP::Get, path, query: query)
    end

    def post(path, payload)
      perform(Net::HTTP::Post, path, body: payload.to_json, content_type: "application/json")
    end

    # Sube un archivo (p. ej. el PDF del ticket) como multipart/form-data.
    def post_multipart(path, fields:, file:)
      boundary = "WhatsApp#{SecureRandom.hex(10)}"
      perform(Net::HTTP::Post, path, body: multipart_body(fields, file, boundary), content_type: "multipart/form-data; boundary=#{boundary}")
    end

    private

    def perform(request_class, path, query: {}, body: nil, content_type: nil)
      uri = URI("#{BASE}/#{API_VERSION}#{path}")
      uri.query = URI.encode_www_form(query) if query.any?

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = @read_timeout

      request = request_class.new(uri)
      request["Authorization"] = "Bearer #{@token}"
      request["Content-Type"] = content_type if content_type
      request.body = body if body

      read(http.request(request))
    rescue *NETWORK_ERRORS => e
      Rails.logger.warn("[Whatsapp::GraphClient] sin respuesta de Meta: #{e.class}")
      Result.new(failure: Failure.new(family: :transient, reason: "meta_unreachable", message: e.class.name))
    end

    def read(response)
      data = parse(response.body)
      return Result.new(data: data) if response.is_a?(Net::HTTPSuccess)

      Result.new(failure: classify(data["error"], response.code.to_i))
    end

    def parse(body)
      parsed = JSON.parse(body.to_s)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    def classify(error, http_status)
      error ||= {}
      code = error["code"].to_i
      subcode = error["error_subcode"]&.to_i
      family, reason = family_and_reason(code, subcode, http_status)
      Rails.logger.warn("[Whatsapp::GraphClient] error de Meta http=#{http_status} code=#{code} family=#{family}")
      Failure.new(family: family, reason: reason, code: code.zero? ? nil : code, subcode: subcode,
                  message: scrub(error["message"]), http_status: http_status)
    end

    def family_and_reason(code, subcode, http_status)
      return [ :connection, subcode == EXPIRED_SUBCODE ? "token_expired" : "invalid_token" ] if code == 190
      return [ :connection, "missing_permission" ] if (200..299).cover?(code) && code != 200
      return [ :connection, CONNECTION_CODES.fetch(code) ] if CONNECTION_CODES.key?(code)
      return [ :template, TEMPLATE_CODES.fetch(code) ] if TEMPLATE_CODES.key?(code)
      return [ :recipient, RECIPIENT_CODES.fetch(code) ] if RECIPIENT_CODES.key?(code)
      return [ :transient, "rate_limited" ] if TRANSIENT_CODES.include?(code)
      return [ :transient, "meta_unreachable" ] if http_status >= 500

      [ :other, "unknown" ]
    end

    # El mensaje de Meta no debe devolver la llave aunque algún día la repita.
    def scrub(message)
      text = message.to_s
      @token.present? ? text.gsub(@token, "[FILTERED]") : text
    end

    def multipart_body(fields, file, boundary)
      crlf = "\r\n"
      "".b.tap do |body|
        fields.each do |name, value|
          body << "--#{boundary}#{crlf}".b
          body << "Content-Disposition: form-data; name=\"#{name}\"#{crlf}#{crlf}".b
          body << "#{value}#{crlf}".b
        end
        body << "--#{boundary}#{crlf}".b
        body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{file.fetch(:filename)}\"#{crlf}".b
        body << "Content-Type: #{file.fetch(:content_type)}#{crlf}#{crlf}".b
        body << file.fetch(:bytes).b
        body << "#{crlf}--#{boundary}--#{crlf}".b
      end
    end
  end
end
