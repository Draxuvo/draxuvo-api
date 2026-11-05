require "net/http"
require "json"

module Push
  # Única salida hacia el servicio de push de Expo (spec 057, research R1). Manda en lotes de 100 y pide recibos.
  # Límite de envío, Expo caído o sin red lanzan `Transient` para que el job reintente; un error de un mensaje concreto
  # (p. ej. `DeviceNotRegistered`) llega en su ticket. `EXPO_ACCESS_TOKEN` es opcional («Enhanced push security»).
  class ExpoClient
    SEND_URL = "https://exp.host/--/api/v2/push/send".freeze
    RECEIPTS_URL = "https://exp.host/--/api/v2/push/getReceipts".freeze
    BATCH = 100
    OPEN_TIMEOUT = 3
    READ_TIMEOUT = 5
    NETWORK_ERRORS = [ Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError ].freeze

    class Transient < StandardError; end

    # Un ticket por mensaje, en el mismo orden: { "status" => "ok", "id" => … } o { "status" => "error", "details" => … }.
    def send_messages(messages)
      messages.each_slice(BATCH).flat_map do |batch|
        tickets = Array(post(SEND_URL, batch)["data"])
        raise Transient, "expo_bad_response" unless tickets.size == batch.size

        tickets
      end
    end

    # { ticket_id => { "status" => …, "details" => … } } de los que Expo ya tiene.
    def receipts(ids)
      ids.each_slice(1000).each_with_object({}) do |batch, acc|
        data = post(RECEIPTS_URL, { ids: batch })["data"]
        acc.merge!(data) if data.is_a?(Hash)
      end
    end

    private

    def post(url, payload)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      token = ENV["EXPO_ACCESS_TOKEN"].presence
      request["Authorization"] = "Bearer #{token}" if token
      request.body = payload.to_json

      read(http.request(request))
    rescue *NETWORK_ERRORS => e
      raise Transient, "expo_unreachable: #{e.class}"
    end

    def read(response)
      code = response.code.to_i
      raise Transient, "expo_http_#{code}" if code == 429 || code >= 500

      data = JSON.parse(response.body.to_s)
      raise Transient, "expo_http_#{code}" unless response.is_a?(Net::HTTPSuccess) && data.is_a?(Hash)

      data
    rescue JSON::ParserError
      raise Transient, "expo_bad_response"
    end
  end
end
