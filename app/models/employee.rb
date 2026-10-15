# app/models/employee.rb
class Employee < ApplicationRecord
  belongs_to :company
  belongs_to :user, optional: true
  has_many :attendances,  dependent: :destroy
  has_many :work_orders,  dependent: :nullify

  enum :status, { active: 0, inactive: 1 }, default: :inactive

  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :email, uniqueness: true, allow_blank: true

  scope :search, ->(q) {
    where("name ILIKE :q OR position ILIKE :q OR department ILIKE :q", q: "%#{q}%") if q.present?
  }

  # Descompone el campo `name` en partes para crear el User asociado.
  # Ej: "Juan Carlos López García" → first: "Juan Carlos", last: "López", second_last: "García"
  def parsed_name_parts
    parts = name.to_s.strip.split
    case parts.length
    when 0, 1
      { first_name: name, last_name: name, second_last_name: name }
    when 2
      { first_name: parts[0], last_name: parts[1], second_last_name: parts[1] }
    else
      { first_name: parts[0..-3].join(" "), last_name: parts[-2], second_last_name: parts[-1] }
    end
  end
end
