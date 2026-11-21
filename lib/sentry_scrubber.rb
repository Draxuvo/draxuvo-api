# Spec 071: último filtro antes de que un evento salga a Sentry (`before_send`). `data_collection` ya apaga lo que el SDK
# junta por su cuenta; esto quita lo que pudiera colarse por otro camino (contexto agregado a mano, otra integración):
# cuerpo, cookies, encabezados salvo User-Agent, query string (enlaces de alta, contraseña y demo llevan tokens; las
# búsquedas, nombres de clientes) y todo dato del usuario salvo su id. Ver specs/071-monitoreo-externo/contracts/error-event.md.
module SentryScrubber
  KEPT_HEADERS = %w[User-Agent].freeze

  def self.call(event, _hint = nil)
    scrub_request(event.request) if event.respond_to?(:request) && event.request
    event.user = scrub_user(event.user) if event.respond_to?(:user=)
    event
  end

  def self.scrub_request(request)
    request.data = nil
    request.cookies = nil
    request.query_string = nil
    request.env = nil if request.respond_to?(:env=)
    request.headers = (request.headers || {}).slice(*KEPT_HEADERS)
    request.url = strip_query(request.url)
  end

  def self.scrub_user(user)
    return {} if user.blank?

    id = user[:id] || user["id"]
    id ? { id: id } : {}
  end

  def self.strip_query(url)
    url&.split(/[?#]/, 2)&.first
  end
end
