class CompanySerializer < ActiveModel::Serializer
  attributes :id, :name, :slug, :parent_company_id, :order_mode, :created_at, :updated_at

  attribute :stripe_id, if: -> { instance_options[:include_stripe] }

  attribute :users_count do
    object.users.size
  end
end
