# Comanda: la tanda de artículos que el mesero manda a la vez. Sin estado propio; se deduce de sus artículos.
class KitchenOrder < ApplicationRecord
  belongs_to :company
  belongs_to :check
  belongs_to :sent_by, class_name: "User"
  has_many :check_items, dependent: :nullify

  validates :number, presence: true, uniqueness: { scope: :check_id }
end
