module TerminalProviders
  # Mercado Pago Point con la API de Orders (spec 069, research R1, R2 y R4). Cada llamada usa el token de la conexión del
  # negocio (OAuth); las credenciales de la aplicación de Draxuvo salen de las variables MERCADO_PAGO_*.
  class MercadoPago < Base
    AUTHORIZE_URL = "https://auth.mercadopago.com/authorization".freeze
    EXPIRATION = "PT3M".freeze # FR-019: 3 minutos
    PDV = "PDV".freeze
    REDIRECT_PATH = "/terminales/mercado-pago".freeze

    def provider = "mercado_pago"

    def available? = client_id.present? && client_secret.present?

    # URL de regreso fija (debe coincidir con la registrada en la aplicación): la página de `ui` que recibe el código.
    def self.redirect_uri
      base = ENV["FRONTEND_URL_UI"].presence || ENV["FRONTEND_URL"].presence || "http://localhost:4200"
      "#{base.to_s.split(',').first.strip.chomp('/')}#{REDIRECT_PATH}"
    end

    def authorize_url(state:, code_challenge:)
      query = { client_id: client_id, response_type: "code", platform_id: "mp", state: state,
                redirect_uri: self.class.redirect_uri, code_challenge: code_challenge, code_challenge_method: "S256" }
      "#{AUTHORIZE_URL}?#{URI.encode_www_form(query)}"
    end

    def exchange_code(code:, code_verifier:)
      body = { client_id: client_id, client_secret: client_secret, grant_type: "authorization_code", code: code,
               redirect_uri: self.class.redirect_uri, code_verifier: code_verifier }
      credentials(Client.new.post("/oauth/token", body: body, auth: false).body)
    end

    def refresh(connection)
      token = connection.renewal_token
      fail!(:connection, :missing_refresh_token) if token.blank?

      body = { client_id: client_id, client_secret: client_secret, grant_type: "refresh_token", refresh_token: token }
      credentials(Client.new.post("/oauth/token", body: body, auth: false).body, label: false)
    end

    def devices(connection, limit:, offset:)
      body = client(connection).get("/terminals/v1/list", query: { limit: limit, offset: offset }).body
      terminals = Array(body.dig("data", "terminals")).map { |raw| device(raw) }
      [ terminals, body.dig("paging", "total").to_i.nonzero? || terminals.size ]
    end

    def prepare_device(connection, device_id)
      current = find_device(connection, device_id)
      return Preparation.new(mode: PDV, restart_required: false) if current.mode == PDV

      body = client(connection).patch("/terminals/v1/setup", body: { terminals: [ { id: device_id, operating_mode: PDV } ] }).body
      mode = Array(body["terminals"]).find { |t| t["id"] == device_id }&.dig("operating_mode") || PDV
      fail!(:device, :device_not_supported) unless mode == PDV
      Preparation.new(mode: mode, restart_required: true)
    rescue Error => e
      raise unless e.failure.declined?

      fail!(:device, :device_not_supported, http_status: e.failure.http_status)
    end

    def create_charge(charge)
      body = {
        type: "point",
        external_reference: charge.external_reference,
        expiration_time: EXPIRATION,
        transactions: { payments: [ { amount: format("%.2f", charge.amount) } ] },
        config: { point: { terminal_id: charge.payment_terminal.device_id, print_on_terminal: "seller_ticket" } },
        description: I18n.t("terminal_charge.provider_description", locale: :es, company: charge.company.name).first(150)
      }
      integration = { platform_id: ENV["MERCADO_PAGO_PLATFORM_ID"], integrator_id: ENV["MERCADO_PAGO_INTEGRATOR_ID"] }.compact_blank
      body[:integration_data] = integration if integration.any?
      order = client(charge.terminal_connection).post("/v1/orders", body: body, idempotency_key: charge.idempotency_key).body
      to_charge(order)
    rescue Error => e
      raise unless e.failure.declined?

      reason = e.failure.reason.include?("amount") ? :amount_out_of_range : e.failure.reason
      reason = :device_offline if e.failure.reason.include?("terminal")
      fail!(:declined, reason, http_status: e.failure.http_status)
    end

    def fetch_charge(charge)
      to_charge(client(charge.terminal_connection).get("/v1/orders/#{order_id!(charge)}").body)
    end

    def cancel_charge(charge)
      current = fetch_charge(charge)
      return :canceled if current.status == "canceled"
      return :not_cancelable unless current.status == "pending"

      headers = current.detail == "at_terminal" || current.detail == "cancellation_requested" ? { "x-allow-cancelable-status" => "at_terminal" } : {}
      response = client(charge.terminal_connection).post("/v1/orders/#{order_id!(charge)}/cancel",
                                                          idempotency_key: "cancel-#{charge.idempotency_key}", headers: headers)
      response.status == 202 ? :requested : :canceled
    rescue Error => e
      raise unless e.failure.conflict?
      return :canceled if e.failure.reason == "order_already_canceled"

      :not_cancelable
    end

    def refund(charge, idempotency_key:)
      response = client(charge.terminal_connection).post("/v1/orders/#{order_id!(charge)}/refund", idempotency_key: idempotency_key)
      refunds = Array(response.body.dig("transactions", "refunds"))
      done = response.body["status"].to_s == "refunded" || refunds.all? { |r| %w[processed approved refunded].include?(r["status"].to_s) }
      ProviderRefund.new(id: refunds.last&.dig("id"), status: done && refunds.any? ? "done" : "requested")
    rescue Error => e
      return ProviderRefund.new(id: nil, status: "done") if e.failure.reason == "order_already_refunded"

      raise
    end

    # Avisos: `orders` (type `order`) y `mp-connect` (desvinculación). La firma se valida siempre (research R4).
    def parse_webhook(body:, headers:, params:)
      data_id = params["data.id"].presence || params.dig("data", "id").presence || body.dig("data", "id")
      Signature.verify!(signature: headers["x-signature"], request_id: headers["x-request-id"], data_id: data_id)

      type = (body["type"].presence || params["type"].presence || body["topic"]).to_s
      action = body["action"].to_s
      case type
      when "order", "orders" then Notice.new(kind: :charge, external_id: data_id.to_s)
      when "mp-connect"
        account = body["user_id"].presence || body.dig("data", "user_id")
        action.include?("unauthoriz") || action.include?("deauthoriz") || action.include?("delete") ? Notice.new(kind: :disconnect, account_id: account.to_s) : nil
      end
    end

    private

    def client_id = ENV["MERCADO_PAGO_CLIENT_ID"]
    def client_secret = ENV["MERCADO_PAGO_CLIENT_SECRET"]

    def client(connection)
      token = connection.token
      fail!(:connection, :token_unreadable) if token.blank?

      Client.new(token: token)
    end

    def order_id!(charge)
      charge.provider_order_id.presence || fail!(:other, :order_missing)
    end

    def find_device(connection, device_id)
      offset = 0
      loop do
        list, total = devices(connection, limit: 50, offset: offset)
        found = list.find { |d| d.id == device_id }
        return found if found

        offset += 50
        fail!(:device, :device_not_found) if offset >= total || list.empty?
      end
    end

    def device(raw)
      id = raw["id"].to_s
      serial = id.split("__").last.to_s
      model = id.split("__").first.to_s.tr("_", " ")
      Device.new(id: id, label: [ model.presence, serial.last(4).presence && "…#{serial.last(4)}" ].compact.join(" · "),
                 mode: raw["operating_mode"].to_s.presence, store_id: raw["store_id"]&.to_s, pos_id: raw["pos_id"]&.to_s,
                 pdv_supported: nil)
    end

    def to_charge(order)
      payment = Array(order.dig("transactions", "payments")).first || {}
      ProviderCharge.new(
        id: order["id"], payment_id: payment["id"], status: StatusMap.status(order), detail: StatusMap.detail(order, payment),
        reference: (payment["reference_id"].presence || payment.dig("reference", "id")).presence&.to_s,
        card_last4: card_last4(payment), payment_type: payment.dig("payment_method", "type"),
        refund_status: StatusMap.refund_status(order)
      )
    end

    def card_last4(payment)
      digits = (payment.dig("payment_method", "last_four_digits") || payment.dig("card", "last_four_digits")).to_s
      digits.match?(/\A\d{4}\z/) ? digits : nil
    end

    def credentials(body, label: true)
      expires_in = body["expires_in"].to_i
      Credentials.new(
        access_token: body["access_token"], refresh_token: body["refresh_token"],
        expires_at: expires_in.positive? ? expires_in.seconds.from_now : 180.days.from_now,
        account_id: body["user_id"]&.to_s, account_label: (label ? account_label(body["access_token"]) : nil),
        live_mode: body.key?("live_mode") ? body["live_mode"] : true, scope: body["scope"]
      )
    end

    # Nombre visible de la cuenta (apodo o correo); si falla no impide conectar.
    def account_label(token)
      return nil if token.blank?

      me = Client.new(token: token).get("/users/me").body
      me["nickname"].presence || me["email"].presence
    rescue Error
      nil
    end
  end
end
