module Whatsapp
  # Lee de Meta el estado de una plantilla (spec 047, research R5). Solo lee: Draxuvo no crea ni edita plantillas.
  #
  #   approved      APPROVED y con el número de variables que espera Draxuvo
  #   pending       PENDING, IN_APPEAL
  #   rejected      REJECTED, PAUSED, DISABLED y los demás estados que impiden usarla (con motivo)
  #   not_found     ninguna plantilla con ese nombre e idioma
  #   incompatible  aprobada, pero con otro número de variables `{{n}}` en el cuerpo (no se puede usar)
  #
  # Si Meta no responde (`unreachable`) no hay estado nuevo: quien llama conserva el anterior. Un fallo de la conexión
  # (llave vencida, sin permiso) llega en `failure` para que `Whatsapp::Health` lo registre.
  class TemplateCheck
    PENDING = %w[PENDING IN_APPEAL].freeze
    UNUSABLE = %w[REJECTED PAUSED DISABLED PENDING_DELETION DELETED ARCHIVED LIMIT_EXCEEDED].freeze
    FIELDS = "name,language,status,rejected_reason,components".freeze
    FIELDS_WITHOUT_REASON = "name,language,status,components".freeze
    # Código de Meta para un campo que no existe en ese objeto: se reintenta sin `rejected_reason`.
    INVALID_FIELD = 100
    VARIABLE = /\{\{\s*(\d+)\s*\}\}/

    Result = Struct.new(:status, :detail, :unreachable, :failure, keyword_init: true) do
      def unreachable? = unreachable == true
    end

    def initialize(client:, waba_id:, name:, language:, expected_variables:)
      @client = client
      @waba_id = waba_id
      @name = name.to_s.strip
      @language = language.to_s.strip
      @expected_variables = expected_variables
    end

    def call
      return Result.new(status: "not_found", detail: I18n.t("whatsapp_admin.reasons.template_missing")) if @name.blank?

      result = list(FIELDS)
      result = list(FIELDS_WITHOUT_REASON) if !result.ok? && result.failure.code == INVALID_FIELD
      return failed(result.failure) unless result.ok?

      interpret(Array(result.data["data"]))
    end

    private

    def list(fields) = @client.get("/#{@waba_id}/message_templates", name: @name, fields: fields, limit: 100)

    def failed(failure)
      return Result.new(unreachable: true, failure: failure) if failure.reason == "meta_unreachable" || failure.transient?

      # Un fallo de la conexión no dice nada de la plantilla: no hay estado nuevo y el fallo va a `Whatsapp::Health`.
      return Result.new(failure: failure) if failure.connection?

      Result.new(status: "not_found", detail: failure.user_message)
    end

    def interpret(templates)
      match = templates.find { |row| row["name"] == @name && row["language"] == @language }
      return Result.new(status: "not_found", detail: not_found_detail(templates)) unless match

      status = match["status"].to_s
      return Result.new(status: "pending", detail: nil) if PENDING.include?(status)
      return Result.new(status: "rejected", detail: rejected_detail(match, status)) if UNUSABLE.include?(status) || status != "APPROVED"

      approved(match)
    end

    def approved(template)
      found = variables_in(template)
      return Result.new(status: "approved", detail: nil) if @expected_variables.nil? || found == @expected_variables

      Result.new(status: "incompatible", detail: I18n.t("whatsapp_admin.reasons.template_variables_count", found: found, expected: @expected_variables))
    end

    def variables_in(template)
      body = Array(template["components"]).find { |component| component["type"].to_s.upcase == "BODY" }
      body.to_h["text"].to_s.scan(VARIABLE).flatten.uniq.size
    end

    def rejected_detail(template, status)
      reason = template["rejected_reason"].to_s
      reason.present? && reason != "NONE" ? "#{status}: #{reason}" : status
    end

    # Existe con ese nombre pero en otros idiomas: se dice cuáles para que el super admin corrija el idioma.
    def not_found_detail(templates)
      languages = templates.select { |row| row["name"] == @name }.map { |row| row["language"] }.compact.uniq
      return I18n.t("whatsapp_admin.reasons.template_missing") if languages.empty?

      I18n.t("whatsapp_admin.reasons.template_other_language", languages: languages.join(", "))
    end
  end
end
