host_options =
  if Rails.env.production?
    { host: ENV["APP_HOST"], protocol: "https" } # APP_HOST: obligatoria, ver required_env.rb
  else
    { host: "localhost", port: 3000 }
  end

Rails.application.routes.default_url_options.merge!(host_options)
