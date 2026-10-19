# Mesa del local. Está ocupada mientras tiene una cuenta abierta; ese estado se deduce, no se guarda.
class DiningTable < ApplicationRecord
  belongs_to :company
  has_many :checks, dependent: :restrict_with_error
  has_one :open_check, -> { where(status: :open) }, class_name: "Check", inverse_of: :dining_table

  validates :name, presence: true, uniqueness: { scope: :company_id }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  def occupied? = checks.status_open.exists?
end
