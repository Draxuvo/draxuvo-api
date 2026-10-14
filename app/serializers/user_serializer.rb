# companies[] lleva el rol del usuario en cada empresa y si es sucursal (spec 004, R16/R17).
# `role` queda por compatibilidad: super_admin o el rol en la primera empresa.
class UserSerializer < ActiveModel::Serializer
  include Rails.application.routes.url_helpers

  attributes :id, :first_name, :middle_name, :last_name, :second_last_name,
             :email, :phone, :role, :active, :description, :avatar_url,
             :created_at, :updated_at, :companies

  def role
    object.compat_role
  end

  def companies
    object.ordered_memberships.map do |membership|
      company = membership.company
      { id: company.id, name: company.name, slug: company.slug, role: membership.role,
        parent_company_id: company.parent_company_id }
    end
  end

  def avatar_url
    return nil unless object.avatar.attached?

    url_for(object.avatar)
  end
end
