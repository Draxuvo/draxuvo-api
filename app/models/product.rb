# app/models/product.rb
class Product < ApplicationRecord
  belongs_to :company
  has_many :stock_movements, dependent: :destroy
  has_many :work_order_items, dependent: :destroy

  before_validation { self.stock ||= 0 }

  validates :name, :sku, presence: true
  validates :sku, uniqueness: { scope: :company_id }
  validates :stock, numericality: { greater_than_or_equal_to: 0 }

  scope :search,       ->(q)   { where("name ILIKE :q OR sku ILIKE :q", q: "%#{q}%") if q.present? }
  scope :available,    ->      { where(available: true) }
  scope :by_category,  ->(cat) { where(category: cat) if cat.present? }
end
