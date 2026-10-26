# Barrera contra efectos externos en una demo (spec 039, FR-006 y FR-007). `Current.demo` lo activa BaseController
# cuando la empresa activa es una demo; los puntos por donde algo sale al exterior (correo, WhatsApp, Stripe) la consultan.
module Demo
  module Guard
    # Código fijo de verificación por WhatsApp en una demo: no se envía nada, pero el flujo sigue funcionando.
    DEMO_OTP = "123456".freeze

    module_function

    def active? = Current.demo == true

    # En una demo lanza Demo::Restricted; fuera de ella no hace nada.
    def restrict!(action)
      raise Restricted.new(action) if active?
    end
  end
end
