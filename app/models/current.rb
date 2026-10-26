# Contexto de la petición en curso (spec 039). `demo` es verdadero cuando la empresa activa es una demo: los puntos por
# donde algo sale al exterior (correo, WhatsApp, Stripe) lo consultan para simular o bloquear.
class Current < ActiveSupport::CurrentAttributes
  attribute :demo
end
