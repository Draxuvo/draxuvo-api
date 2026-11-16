class CompanySerializer < ActiveModel::Serializer
  attributes :id, :name, :slug, :parent_company_id, :order_mode, :created_at, :updated_at

  attribute :stripe_id, if: -> { instance_options[:include_stripe] }

  # Spec 063: el logo de la empresa ({ url, updated_at, updated_by }) o null.
  attribute :logo do
    object.logo_payload
  end

  attribute :users_count do
    object.users.size
  end
end
