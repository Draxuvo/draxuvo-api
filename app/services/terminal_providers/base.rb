# Interfaz común de los proveedores de terminal integrada (spec 069, FR-005, research R10). Lo común (conexiones, terminales,
# solicitudes de cobro, reembolsos y avisos) vive fuera de aquí; cada proveedor solo traduce entre Draxuvo y su API.
# Sumar un proveedor = una subclase que implemente estos métodos y su registro en `TerminalProviders::REGISTRY`.
#
# Ningún método guarda nada en la base: reciben modelos y devuelven estructuras. Los errores del proveedor se lanzan como
# `TerminalProviders::Error` con una `Failure` que dice qué hacer:
#
#   connection  el token o la cuenta ya no sirven              → la conexión pasa a «Con error»
#   device      la terminal no existe o no admite el modo       → se explica al usuario
#   declined    el proveedor rechazó el cobro o el monto        → la solicitud se rechaza
#   conflict    estado o idempotencia (no se puede cancelar…)   → lo interpreta quien llama
#   transient   proveedor caído, límite o tiempo agotado        → se reintenta después
#   other       cualquier otro rechazo
module TerminalProviders
  class Base
    def provider = raise(NotImplementedError)

    # ¿Tiene la plataforma lo necesario para usar este proveedor (credenciales de la aplicación)?
    def available? = raise(NotImplementedError)

    # Autorización por OAuth. `authorize_url` recibe el `state` y el `code_challenge` (S256) ya generados.
    def authorize_url(state:, code_challenge:) = raise(NotImplementedError)
    def exchange_code(code:, code_verifier:) = raise(NotImplementedError)
    def refresh(connection) = raise(NotImplementedError)

    # Dispositivos de la cuenta, paginados por el proveedor: devuelve [devices, total].
    def devices(connection, limit:, offset:) = raise(NotImplementedError)

    # Deja el dispositivo listo para recibir cobros desde Draxuvo.
    def prepare_device(connection, device_id) = raise(NotImplementedError)

    # Cobros. Reciben la `TerminalCharge`.
    def create_charge(charge) = raise(NotImplementedError)
    def fetch_charge(charge) = raise(NotImplementedError)

    # Devuelve :canceled (cancelado ya), :requested (se resolverá con el aviso) o :not_cancelable.
    def cancel_charge(charge) = raise(NotImplementedError)

    # Reembolso total de un cobro aprobado. `idempotency_key` la decide quien llama (research R8).
    def refund(charge, idempotency_key:) = raise(NotImplementedError)

    # Valida un aviso (cuerpo, encabezados y query) y lo traduce a un `Notice`, o nil si no interesa.
    def parse_webhook(body:, headers:, params:) = raise(NotImplementedError)

    private

    def fail!(family, reason, http_status: nil, message: nil)
      raise Error.new(Failure.new(family: family, reason: reason.to_s, http_status: http_status, message: message))
    end
  end
end
