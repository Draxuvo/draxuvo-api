# Spec 071 (US3): campos propios de la línea JSON de cada petición en producción (config/initializers/lograge.rb).
# Lograge ya pone método, ruta, controlador, acción, estado y duraciones; aquí se suman el request_id, el usuario, la
# empresa, si es demo y, en un 500, solo la clase de la excepción (lograge ya quita el query string de `path`). Nunca
# parámetros, cuerpo ni encabezados. Forma completa: specs/071-monitoreo-externo/contracts/log-line.md.
module RequestLog
  # Rutas que llevan un identificador secreto en la ruta misma (no en el query string): la URL de avisos de una conexión
  # con credenciales propias de la terminal integrada (spec 069, `POST /api/v1/webhooks/mercado_pago/:token`).
  SECRET_SEGMENTS = %r{(/webhooks/mercado_pago/)[^/?#]+}
  FILTERED = "[FILTERED]".freeze

  # La ruta con esos identificadores tapados; también la usa `SentryScrubber` para la URL del evento.
  def self.filter_path(path)
    path&.gsub(SECRET_SEGMENTS, "\\1#{FILTERED}")
  end

  def self.custom_options(event)
    payload = event.payload
    options = {
      request_id: payload[:request_id],
      user_id: payload[:user_id],
      company_id: payload[:company_id],
      demo: payload[:demo]
    }
    path = payload[:path].to_s
    options[:path] = filter_path(path.split("?", 2).first) if path.match?(SECRET_SEGMENTS)
    exception = payload[:exception]
    options[:exception] = exception.first if exception.is_a?(Array) && exception.first
    options
  end
end
