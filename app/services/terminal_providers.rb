# Registro de proveedores de terminal integrada (spec 069). `TerminalProviders.for("mercado_pago")` devuelve el adaptador.
# En pruebas se reemplaza con `TerminalProviders.stub(:for, proveedor_falso)` (test/support/terminal_provider_helpers.rb).
module TerminalProviders
  # Un dispositivo de la cuenta en el proveedor.
  Device = Struct.new(:id, :label, :mode, :store_id, :pos_id, :pdv_supported, keyword_init: true)

  # Lo que el proveedor sabe de un cobro. `status` ya viene en el vocabulario de Draxuvo (pending, approved, declined,
  # canceled, expired, refunded); `detail` es el detalle normalizado (rejected_by_issuer, canceled_on_terminal, …).
  ProviderCharge = Struct.new(:id, :payment_id, :status, :detail, :reference, :card_last4, :payment_type, :refund_status,
                              keyword_init: true)

  # Resultado de pedir un reembolso: `status` es `done` o `requested` (en proceso en el proveedor).
  ProviderRefund = Struct.new(:id, :status, keyword_init: true)

  # Resultado de preparar un dispositivo para cobrar desde Draxuvo.
  Preparation = Struct.new(:mode, :restart_required, keyword_init: true)

  # Credenciales que devuelve una autorización o una renovación.
  Credentials = Struct.new(:access_token, :refresh_token, :expires_at, :account_id, :account_label, :live_mode, :scope,
                           keyword_init: true)

  # Aviso del proveedor ya validado: `kind` es :charge (con `external_id` del cobro) o :disconnect (con `account_id`).
  Notice = Struct.new(:kind, :external_id, :account_id, keyword_init: true)

  Failure = Struct.new(:family, :reason, :http_status, :message, keyword_init: true) do
    def connection? = family == :connection
    def transient? = family == :transient
    def conflict? = family == :conflict
    def declined? = family == :declined
    def device? = family == :device
  end

  # Error de un proveedor. `failure.reason` es un código corto y estable (sin datos del proveedor que puedan llevar secretos).
  class Error < StandardError
    attr_reader :failure

    def initialize(failure)
      @failure = failure
      super("#{failure.family}: #{failure.reason}")
    end
  end

  # La firma de un aviso no es válida (o falta el secreto para validarla).
  class InvalidSignature < StandardError; end

  REGISTRY = { "mercado_pago" => "TerminalProviders::MercadoPago" }.freeze

  module_function

  def for(provider)
    klass = REGISTRY[provider.to_s] or raise ArgumentError, "proveedor de terminal desconocido: #{provider}"
    klass.constantize.new
  end

  def providers = REGISTRY.keys
end
