class StockCountItem < ApplicationRecord
  belongs_to :stock_count
  belongs_to :product

  validates :counted_qty, numericality: { greater_than_or_equal_to: 0 }
  validate :whole_quantity, unless: -> { product&.fractional? }
  validate :product_counted

  private

  def whole_quantity
    errors.add(:counted_qty, :integer_only) if counted_qty && counted_qty.to_d != counted_qty.to_d.round
  end

  def product_counted
    errors.add(:product, :not_counted) if product && !product.counted?
  end
end
