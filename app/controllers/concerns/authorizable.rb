# Permisos por rol de la empresa activa (R16): current_role es super_admin o el rol de la membresía.
module Authorizable
  extend ActiveSupport::Concern

  ADMIN_ROLES = %w[admin owner super_admin].freeze
  BOSS_ROLES = %w[admin owner super_admin].freeze

  private

  def require_super_admin!
    forbid! unless current_user&.super_admin?
  end

  def require_admin!
    forbid! unless ADMIN_ROLES.include?(current_role)
  end

  def require_boss!
    forbid! unless BOSS_ROLES.include?(current_role)
  end

  def require_owner!
    forbid! unless %w[owner super_admin].include?(current_role)
  end

  def forbid!(details: nil)
    raise ApiErrors::ForbiddenError.new(message: I18n.t("auth.not_authorized"), details: details)
  end
end
