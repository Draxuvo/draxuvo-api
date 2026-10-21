# Tipo de producto de una empresa (spec 016). Sus reglas deciden si sus productos salen en el menú y las órdenes
# (sellable), si llevan existencia, se descuentan y se agotan (counted) y si admiten decimales (fractional).
class ProductType < ApplicationRecord
  belongs_to :company
  has_many :products, dependent: :restrict_with_error

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, length: { maximum: 40 }, uniqueness: { scope: :company_id, case_sensitive: false }
  before_validation { self.icon = icon.presence }
  validates :icon, inclusion: { in: ->(_) { ProductIcons.keys } }, allow_nil: true
  validate :fractional_requires_counted
  validate :default_unit_exists
  validate :fractions_fit, if: -> { will_save_change_to_fractional?(to: false) }

  after_update :sync_products, if: :saved_change_to_counted?

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  def default_unit = Unit.find_by(key: default_unit_key)

  # Nombres de los productos con existencia con fracción, que impiden quitar los decimales.
  def products_with_fractions
    products.where("stock <> ROUND(stock) OR min_stock <> ROUND(min_stock)").order(:name).limit(10).pluck(:name)
  end

  private

  def fractional_requires_counted
    errors.add(:fractional, :invalid) if fractional && !counted
  end

  def default_unit_exists
    errors.add(:default_unit_key, :inclusion) unless Unit.exists?(key: default_unit_key)
  end

  def fractions_fit
    errors.add(:fractional, :fractional_stock) if products_with_fractions.any?
  end

  # `tracks_stock` sigue siendo lo que leen el menú y el descuento del restaurante (research R2).
  def sync_products
    products.update_all(tracks_stock: counted, updated_at: Time.current)
  end
end
