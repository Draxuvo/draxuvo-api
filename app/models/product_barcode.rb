# Código de barras de un producto (spec 034). Único por empresa; un producto puede tener varios.
class ProductBarcode < ApplicationRecord
  belongs_to :company
  belongs_to :product

  before_validation { self.code = code.to_s.strip }
  validates :code, presence: true, length: { maximum: 64 }
  validates :code, uniqueness: { scope: :company_id }
  validate :product_in_company

  private

  def product_in_company
    errors.add(:product, :invalid) if product && product.company_id != company_id
  end
end
