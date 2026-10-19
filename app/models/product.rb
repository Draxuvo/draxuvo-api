# app/models/product.rb
class Product < ApplicationRecord
  belongs_to :company
  has_many :stock_movements, dependent: :destroy
  has_many :work_order_items, dependent: :destroy
  belongs_to :station, optional: true
  has_many :check_items, dependent: :nullify

  before_validation { self.stock ||= 0 }
  validate :station_in_company

  validates :name, :sku, presence: true
  validates :sku, uniqueness: { scope: :company_id }
  validates :stock, numericality: { greater_than_or_equal_to: 0 }

  scope :search,       ->(q)   { where("name ILIKE :q OR sku ILIKE :q", q: "%#{q}%") if q.present? }
  scope :tracked,      ->      { where(tracks_stock: true) }
  scope :available,    ->      { where(available: true) }
  scope :by_category,  ->(cat) { where(category: cat) if cat.present? }

  private

  def station_in_company
    errors.add(:station, :invalid) if station && station.company_id != company_id
  end
end
