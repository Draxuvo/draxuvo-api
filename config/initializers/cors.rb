# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
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
