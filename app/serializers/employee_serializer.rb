# app/serializers/employee_serializer.rb
class EmployeeSerializer < ActiveModel::Serializer
  attributes :id, :user_id, :name, :email, :phone, :position, :department, :salary, :status,
             :created_at, :updated_at

  # Spec 036: el acceso (rol del usuario ligado) solo lo ve quien lo administra (`include_access: true`).
  attribute :access, if: -> { instance_options[:include_access] } do
    next nil unless object.user

    {
      id:     object.user.id,
      email:  object.user.email,
      role:   object.user.role_in(object.company),
      active: object.user.active
    }
  end
end
