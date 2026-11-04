# Una anulación del cobro de un ticket (spec 054, H-50): quién, cuándo, por qué y qué pagos se anularon. El ticket
# conserva su folio al volver a cobrarse, así que este historial es lo que deja rastro. Solo inserción.
class TicketVoid < ApplicationRecord
  belongs_to :company
  belongs_to :ticket
  belongs_to :voided_by, class_name: "User"

  validates :voided_at, presence: true
  validates :reason, presence: true, length: { maximum: 500 }
  validates :amount, numericality: { greater_than_or_equal_to: 0 }
end
