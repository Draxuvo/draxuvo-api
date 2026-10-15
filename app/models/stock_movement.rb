# app/models/stock_movement.rb
class StockMovement < ApplicationRecord
  belongs_to :product
  belongs_to :company

  enum :movement_type, { entry: 0, exit: 1, adjustment: 2 }

  validates :qty, presence: true, numericality: { other_than: 0 }
  validate :adjustment_keeps_stock_non_negative, on: :create

  scope :search, ->(q) {
    joins(:product).where("products.name ILIKE :q OR stock_movements.note ILIKE :q", q: "%#{q}%") if q.present?
  }

  after_create :update_stock

  private

  # increment! no pasa por las validaciones de Product, así que se revisa aquí.
  def adjustment_keeps_stock_non_negative
    return unless adjustment? && qty.to_i.negative? && product
    return if product.stock.to_i + qty >= 0

    errors.add(:qty, :greater_than_or_equal_to, count: -product.stock.to_i)
  end

  # entry suma y exit resta el valor absoluto; adjustment respeta el signo de qty.
  def update_stock
    delta = case movement_type
    when "exit" then -qty.abs
    when "adjustment" then qty
    else qty.abs
    end
    product.increment!(:stock, delta)
  end
end
