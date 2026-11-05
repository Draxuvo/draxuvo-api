module Push
  # Manda un aviso a una persona en todos sus dispositivos activos y lo deja en la bitácora (spec 057, FR-015, FR-022,
  # FR-023). Quien no es elegible no se registra; quien apagó el tipo o no tiene dispositivos queda registrado con ese
  # motivo. `DeviceNotRegistered` desactiva el dispositivo (FR-004). Un fallo transitorio de Expo sube como
  # `ExpoClient::Transient` para que el job reintente.
  class Deliver
    def self.call(**args) = new(**args).call

    def initialize(company:, user:, message:, subject_key:, attempt: 1, client: ExpoClient.new)
      @company = company
      @user = user
      @message = message
      @subject_key = subject_key
      @attempt = attempt
      @client = client
    end

    def call
      status = Eligibility.recipient_status(@user, @company, @message.kind)
      return nil if status == :ineligible
      return record(status.to_s) unless status == :ok

      devices = @user.push_devices.active.order(:id).to_a
      tickets = @client.send_messages(devices.map { |device| @message.for_device(device) })
      outcome(devices, tickets)
    end

    # Registro sin envío (p. ej. «fuera de turno» o «vencido»), con la misma forma que uno enviado.
    def self.record(company:, user:, kind:, subject_key:, status:, error: nil, attempts: 1)
      PushDelivery.create!(company: company, user: user, kind: kind.to_s, subject_key: subject_key, status: status,
                           error: error&.truncate(200), attempts: attempts)
    end

    private

    def outcome(devices, tickets)
      ok = []
      errors = []
      devices.zip(tickets).each do |device, ticket|
        if ticket["status"] == "ok"
          ok << { "id" => ticket["id"], "device_id" => device.id }
        else
          reason = ticket.dig("details", "error") || ticket["message"].to_s.first(80)
          device.disable!("not_registered") if reason == "DeviceNotRegistered"
          errors << reason
        end
      end

      status = if ok.any? then "sent"
      elsif errors.all?("DeviceNotRegistered") then "invalid_device"
      else "failed"
      end
      PushDelivery.create!(company: @company, user: @user, kind: @message.kind, subject_key: @subject_key, status: status,
                           devices_count: devices.size, tickets: ok, attempts: @attempt,
                           error: errors.uniq.join(", ").presence&.truncate(200))
    end

    def record(status)
      self.class.record(company: @company, user: @user, kind: @message.kind, subject_key: @subject_key, status: status,
                        attempts: @attempt)
    end
  end
end
