module Authenticable
  include JwtHelper
  include ApiErrors

  def authenticate_request
    authorization_header = request.headers["Authorization"]

    unless authorization_header
      raise ApiErrors::UnauthorizedError.new(message: I18n.t("auth.header_missing"))
    end

    token = authorization_header.split(" ").last

    begin
      decoded        = jwt_decode(token)
      @current_user  = User.find(decoded[:user_id])
    rescue ActiveRecord::RecordNotFound
      raise ApiErrors::UnauthorizedError.new(
        message: I18n.t("auth.invalid_credentials"),
        details: I18n.t("auth.user_not_found_token"),
      )
    rescue JWT::ExpiredSignature
      raise ApiErrors::UnauthorizedError.new(
        message: I18n.t("auth.token_expired"),
        details: I18n.t("auth.relogin"),
      )
    rescue JWT::DecodeError => e
      raise ApiErrors::UnauthorizedError.new(
        message: I18n.t("auth.invalid_token"),
        details: e.message,
      )
    rescue => e
      raise ApiErrors::UnauthorizedError.new(
        message: I18n.t("auth.failed"),
        details: e.message,
      )
    end

    # Spec 052 (H-04): una cuenta desactivada pierde el acceso en la siguiente petición, aunque su token siga vigente.
    raise ApiErrors::UnauthorizedError.new(message: I18n.t("auth.account_inactive")) if @current_user.locked?
  end

  def current_user
    @current_user
  end
end
