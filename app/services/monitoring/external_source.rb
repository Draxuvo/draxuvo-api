# Base de los clientes de terceros del estado del sistema (spec 073, research R11–R13). Una petición GET con el token en
# el encabezado y tiempos límite cortos. Clasifica la falla sin lanzar nunca: sin token es `unconfigured`, 401/403 es
# `invalid_token` y lo demás es `unreachable`. El token no se escribe en el log ni sale en el resultado.
module Monitoring
  class ExternalSource
    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 3

    Response = Struct.new(:status, :body)

    # `http` se inyecta en las pruebas: recibe la URI y los encabezados y devuelve un Response.
    def initialize(token: nil, http: nil)
      @token = token.presence
      @http = http || method(:default_http)
    end

    def call
      return log(unconfigured) unless @token

      log(fetch)
    rescue TokenRejected
      log(failure("invalid_token", "token_rejected"))
    rescue HttpError => error
      log(failure("unreachable", error.message))
    rescue StandardError => error
      log(failure("unreachable", error.class.name))
    end

    private

    def fetch = raise(NotImplementedError)

    def get_json(url, params = {})
      uri = URI(url)
      uri.query = URI.encode_www_form(params) if params.any?
      response = @http.call(uri, { "Authorization" => "Bearer #{@token}", "Accept" => "application/json" })
      raise TokenRejected if [ 401, 403 ].include?(response.status)
      raise HttpError, "http_#{response.status}" unless (200..299).cover?(response.status)

      JSON.parse(response.body.to_s)
    end

    def default_http(uri, headers)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      request = Net::HTTP::Get.new(uri)
      headers.each { |key, value| request[key] = value }
      response = http.request(request)
      Response.new(response.code.to_i, response.body)
    end

    def unconfigured = failure("unconfigured", "missing_token")

    def failure(state, reason) = { state: state, reason: reason }

    def log(result)
      Rails.logger.info("[#{self.class.name}] #{result[:state]}#{" (#{result[:reason]})" if result[:reason]}")
      result
    end

    class TokenRejected < StandardError; end
    class HttpError < StandardError; end
  end
end
