# Spec 071 (US3): campos propios de la línea JSON de cada petición en producción (config/initializers/lograge.rb).
# Lograge ya pone método, ruta, controlador, acción, estado y duraciones; aquí se suman el request_id, el usuario, la
# empresa, si es demo y, en un 500, solo la clase de la excepción (lograge ya quita el query string de `path`). Nunca
# parámetros, cuerpo ni encabezados. Forma completa: specs/071-monitoreo-externo/contracts/log-line.md.
module RequestLog
  def self.custom_options(event)
    payload = event.payload
    options = {
      request_id: payload[:request_id],
      user_id: payload[:user_id],
      company_id: payload[:company_id],
      demo: payload[:demo]
    }
    exception = payload[:exception]
    options[:exception] = exception.first if exception.is_a?(Array) && exception.first
    options
  end
end
