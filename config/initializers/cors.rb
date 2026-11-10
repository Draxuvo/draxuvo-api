# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  # Menú público de las mesas (spec 059): lo pide el teléfono del comensal desde el sitio público (`web`), sin
  # sesión. Solo ese origen, solo lectura y sin credenciales; la desviación de FRONTEND_URL está justificada en
  # specs/059-menu-qr-mesas/plan.md (Complexity Tracking). Va primero: rack-cors usa el primer bloque que coincide.
  allow do
    public_origins = [
      # Mismo valor que DiningTable.public_site_url (no se usa el modelo: no se autocarga código al arrancar).
      ENV.fetch("PUBLIC_SITE_URL", Rails.env.production? ? "https://draxuvo.com" : "http://localhost:4300").chomp("/"),
      ("http://localhost:4300" if Rails.env.development? || Rails.env.test?)
    ].compact.reject(&:empty?).uniq
    origins(*public_origins)

    resource "/api/v1/public/*",
      headers:     :any,
      methods:     %i[get options],
      credentials: false
  end

  allow do
    allowed_origins = [
      ENV["FRONTEND_URL"],
      ENV["FRONTEND_URL_UI"],
      ("http://localhost:4200" if Rails.env.development? || Rails.env.test?)
    ].compact.reject(&:empty?)
    origins(*allowed_origins)

    resource "*",
      headers:  :any,
      methods:  [ :get, :post, :put, :patch, :delete, :options, :head ],
      expose:   [ "Authorization" ]
  end
end
