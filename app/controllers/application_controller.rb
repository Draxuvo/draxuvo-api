class ApplicationController < ActionController::API
  include ErrorHandler
  include Authenticable
  include Pagy::Backend
  include PaginationConcern

  before_action :set_locale
  before_action :authenticate_request, unless: :authentication_controller?

  private

  # Spec 071 (US3): datos de la línea JSON de la petición (lib/request_log.rb). Solo lo que ya se cargó: no fuerza la
  # consulta del usuario ni de la empresa, y las rutas sin sesión los dejan vacíos.
  def append_info_to_payload(payload)
    super
    payload[:request_id] = request.request_id
    payload[:user_id] = @current_user&.id
    payload[:company_id] = @current_company&.id
    payload[:demo] = Current.demo
  end

  def set_locale
    header = request.env["HTTP_LOCALE"] || request.env["HTTP_ACCEPT_LANGUAGE"]
    lang   = header&.split(",")
                   &.map { |l| l.split(";").first.split("-").first.strip.downcase.to_sym }
                   &.find { |l| I18n.available_locales.include?(l) }
    I18n.locale = lang || I18n.default_locale
  end

  def authentication_controller?
    self.class.module_parent == Api::V1 &&
    self.class.name.demodulize == "AuthenticationController"
  end
end
