# Spec 071 (US1): latido del worker de trabajos en segundo plano hacia Better Stack. Corre como trabajo recurrente
# (config/recurring.yml, cada 5 minutos): si llega, el programador, el despachador, los trabajadores y la conexión a la
# base funcionan; si deja de llegar (worker caído o atorado), Better Stack avisa. Sin HEARTBEAT_URL no hace nada.
# La URL es secreta (quien la conoce mantiene vivo el monitor): nunca se escribe en el log.
module Monitoring
  class HeartbeatJob < ApplicationJob
    queue_as :default

    TIMEOUT = 5
    NETWORK_ERRORS = [ Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Net::ProtocolError ].freeze

    # Un latido perdido no se reintenta: el siguiente sale en 5 minutos.
    discard_on StandardError

    def perform
      url = ENV["HEARTBEAT_URL"].presence
      return unless url

      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT
      response = http.request(Net::HTTP::Get.new(uri))
      Rails.logger.warn("[Monitoring::HeartbeatJob] respuesta #{response.code}") unless response.is_a?(Net::HTTPSuccess)
    rescue *NETWORK_ERRORS => e
      Rails.logger.warn("[Monitoring::HeartbeatJob] sin latido: #{e.class}")
    end
  end
end
