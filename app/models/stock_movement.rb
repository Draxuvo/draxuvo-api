# app/models/stock_movement.rb
class StockMovement < ApplicationRecord
  belongs_to :product
  belongs_to :company
  belongs_to :user, optional: true
  belongs_to :sale, optional: true
  belongs_to :work_order, optional: true

  enum :movement_type, { entry: 0, exit: 1, adjustment: 2 }, validate: true

  validates :movement_type, presence: true
  validates :qty, presence: true, numericality: { less_than: 100_000_000 }
  # Spec 054 (H-54): una entrada o una salida es una cantidad positiva (el sentido lo da el tipo). Solo el ajuste del
  # conteo físico lleva signo.
  validates :qty, numericality: { greater_than: 0 }, allow_nil: true, unless: :adjustment?
  validates :qty, numericality: { other_than: 0 }, allow_nil: true, if: :adjustment?
  validate :adjustment_keeps_stock_non_negative, on: :create
  validate :exit_within_stock, on: :create, unless: :initial?
  validate :whole_quantity, unless: -> { product&.fractional? }

  scope :search, ->(q) {
    joins(:product).where("products.name ILIKE :q OR stock_movements.note ILIKE :q", q: "%#{q}%") if q.present?
  }

  after_create :update_stock, unless: :initial?

  private

  # increment! no pasa por las validaciones de Product, así que se revisa aquí.
  def adjustment_keeps_stock_non_negative
    return unless adjustment? && qty.to_d.negative? && product
    return if product.stock.to_d + qty >= 0

    errors.add(:qty, :greater_than_or_equal_to, count: -product.stock.to_d)
  end

  # Spec 052 (H-08): una salida nunca deja la existencia por debajo de cero, llegue como llegue la petición.
  def exit_within_stock
    return unless exit? && product
    return if product.stock.to_d >= qty.to_d.abs

    errors.add(:qty, :insufficient_stock, available: Product.quantity(product.stock))
  end

  # Solo los tipos con decimales (spec 016) aceptan fracciones.
  def whole_quantity
    errors.add(:qty, :integer_only) if qty && qty.to_d != qty.to_d.round
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
