module Whatsapp
  # Verifica una conexión contra Meta antes de guardarla (spec 047): que la llave sirva, que el número exista y que
  # pertenezca a la cuenta de WhatsApp Business indicada. Solo lee: no manda mensajes ni guarda nada.
  #
  # El resultado dice `ok` con el nombre y el número visibles, o el `reason` del rechazo (las claves de
  # `whatsapp_admin.reasons`), o `unreachable` cuando Meta no respondió (no es un rechazo: no se cambia ningún estado).
  class ConnectionCheck
    DIGITS = /\A\d{6,20}\z/
    PHONE_FIELDS = "verified_name,display_phone_number".freeze
    # Meta responde 100 cuando el identificador no existe o no se puede consultar con esa llave.
    OBJECT_NOT_FOUND = 100

    Result = Struct.new(:ok, :reason, :meta_code, :unreachable, :verified_name, :display_phone_number, keyword_init: true) do
      def ok? = ok == true
      def unreachable? = unreachable == true

      def message = I18n.t("whatsapp_admin.reasons.#{reason}", default: I18n.t("whatsapp_admin.reasons.unknown"))
    end

    def initialize(token:, phone_number_id:, waba_id:, client: nil)
      @token = token.to_s.strip
      @phone_number_id = phone_number_id.to_s.strip
      @waba_id = waba_id.to_s.strip
      @client = client || Whatsapp::GraphClient.new(token: @token)
    end

    def call
      return rejected("invalid_number") unless @phone_number_id.match?(DIGITS)
      return rejected("account_not_found") unless @waba_id.match?(DIGITS)

      phone = @client.get("/#{@phone_number_id}", fields: PHONE_FIELDS)
      return failed(phone.failure, not_found: "invalid_number") unless phone.ok?

      numbers = @client.get("/#{@waba_id}/phone_numbers", fields: "id", limit: 100)
      return failed(numbers.failure, not_found: "account_not_found") unless numbers.ok?
      return rejected("phone_not_in_account") unless belongs?(numbers.data)

      Result.new(ok: true, verified_name: phone.data["verified_name"], display_phone_number: phone.data["display_phone_number"])
    end

    private

    def belongs?(data)
      Array(data["data"]).any? { |row| row["id"].to_s == @phone_number_id }
    end

    def rejected(reason, meta_code: nil) = Result.new(ok: false, reason: reason, meta_code: meta_code)

    # Traduce el fallo de Meta: sin respuesta o Meta caído → inalcanzable; de la conexión → su motivo; objeto inexistente → `not_found`.
    def failed(failure, not_found:)
      return Result.new(ok: false, unreachable: true, reason: "meta_unreachable") if failure.reason == "meta_unreachable"
      return rejected(failure.reason, meta_code: failure.code) if failure.connection?
      return rejected(not_found, meta_code: failure.code) if failure.code == OBJECT_NOT_FOUND || failure.http_status == 404

      rejected(failure.transient? ? "rate_limited" : "unknown", meta_code: failure.code)
    end
  end
end
