# Mesa del local. Está ocupada mientras tiene una cuenta abierta; ese estado se deduce, no se guarda.
class DiningTable < ApplicationRecord
  belongs_to :company
  has_many :checks, dependent: :restrict_with_error
  has_one :open_check, -> { where(status: :open) }, class_name: "Check", inverse_of: :dining_table

  validates :name, presence: true, uniqueness: { scope: :company_id }
  # Spec 054 (H-47): solo se exige al crear o cambiar el nombre; una mesa vieja con un nombre largo se sigue editando.
  validates :name, length: { maximum: 100 }, if: :will_save_change_to_name?

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  def occupied? = checks.status_open.exists?
end
