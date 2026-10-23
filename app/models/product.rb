# app/models/product.rb
class Product < ApplicationRecord
  belongs_to :company
  belongs_to :product_type
  has_many :stock_movements, dependent: :destroy
  has_many :work_order_items, dependent: :destroy
  belongs_to :station, optional: true
  has_many :check_items, dependent: :nullify
  has_many :barcodes, -> { order(:id) }, class_name: "ProductBarcode", dependent: :destroy

  before_validation { self.stock ||= 0 }
  # Sin tipo (formularios o archivos anteriores), se clasifica con la regla de los tipos iniciales (spec 016).
  before_validation { self.product_type ||= ProductTypes::Defaults.classify(company, self) if company }
  before_validation { self.tracks_stock = product_type.counted if product_type }
  validate :station_in_company
  validate :type_in_company
  validate :whole_quantities, unless: -> { product_type&.fractional? }

  delegate :sellable?, :counted?, :fractional?, to: :product_type, allow_nil: true

  before_validation { self.icon = icon.presence }
  validates :icon, inclusion: { in: ->(_) { ProductIcons.keys } }, allow_nil: true
  validates :name, :sku, presence: true
  validates :sku, uniqueness: { scope: :company_id }
  validates :stock, numericality: { greater_than_or_equal_to: 0 }

  # Nombre, SKU o cualquiera de sus códigos de barras (spec 034).
  scope :search,       ->(q)   {
    next if q.blank?

    where("products.name ILIKE :q OR products.sku ILIKE :q OR EXISTS (SELECT 1 FROM product_barcodes pb WHERE pb.product_id = products.id AND pb.code ILIKE :q)",
          q: "%#{sanitize_sql_like(q.to_s.strip)}%")
  }
  scope :tracked,      ->      { where(tracks_stock: true) }
  scope :available,    ->      { where(available: true) }
  scope :by_category,  ->(cat) { where(category: cat) if cat.present? }
  scope :sellable,     ->      { joins(:product_type).where(product_types: { sellable: true }) }
  # Menú del restaurante (spec 032): se vende y el tipo está en el menú.
  scope :on_menu,      ->      { joins(:product_type).where(product_types: { sellable: true, in_menu: true }) }
  scope :counted,      ->      { joins(:product_type).where(product_types: { counted: true }) }
  # Bajo inventario (spec 016, FR-013): solo tipos que se cuentan, con mínimo y existencia en el mínimo o debajo.
  scope :low_stock,    ->      { counted.where("products.min_stock > 0 AND products.stock <= products.min_stock") }

  # Cantidad para JSON (spec 016): entero si no tiene fracción, decimal si la tiene; nunca texto.
  def self.quantity(value)
    return nil if value.nil?

    value = value.to_d
    value == value.round ? value.to_i : value.to_f
  end

  def barcode_codes = barcodes.map(&:code)

  # Reemplaza la lista de códigos (formulario del producto); quita los que ya no están y agrega los nuevos.
  def replace_barcodes!(codes)
    wanted = Products::Barcodes.clean_list(codes)
    barcodes.where.not(code: wanted).destroy_all
    (wanted - barcodes.reload.map(&:code)).each { |code| barcodes.create!(company: company, code: code) }
    barcodes.reset
  end

  def unit
    Unit.find_by(key: unit_key.presence || product_type&.default_unit_key)
  end

  def low_stock? = !!(counted? && min_stock.to_d.positive? && stock.to_d <= min_stock.to_d)

  private

  def station_in_company
    errors.add(:station, :invalid) if station && station.company_id != company_id
  end

  def type_in_company
    errors.add(:product_type, :invalid) if product_type && product_type.company_id != company_id
  end

  def whole_quantities
    %i[stock min_stock].each do |field|
      value = self[field]
      errors.add(field, :integer_only) if value && value.to_d != value.to_d.round
    end
  end
end
