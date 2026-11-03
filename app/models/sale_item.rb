# Un producto dentro de una venta (spec 050). Guarda el nombre, la clave y el precio del momento: un cambio posterior
# en Inventario no altera la venta ni su ticket. `stock_taken` es lo que se descontó de verdad al cobrar.
class SaleItem < ApplicationRecord
  belongs_to :sale
  belongs_to :company
  belongs_to :product, optional: true

  validates :name, presence: true
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity, numericality: { greater_than: 0 }
  validate :whole_quantity
  validate :sale_is_open, on: :create
  validate :same_company

  before_validation :compute_subtotal

  private

  def compute_subtotal
    self.subtotal = (quantity.to_d * unit_price.to_d).round(2) if quantity && unit_price
  end

  # Solo los tipos que admiten decimales (spec 016) se venden por fracción.
  def whole_quantity
    return unless quantity && product && !product.fractional?

    errors.add(:quantity, :integer_only) if quantity.to_d != quantity.to_d.round
  end

  def sale_is_open
    errors.add(:sale, :invalid) if sale && !sale.status_open?
  end

  def same_company
    errors.add(:company, :invalid) if sale && company_id != sale.company_id
    errors.add(:product, :invalid) if product && product.company_id != company_id
  end
end
