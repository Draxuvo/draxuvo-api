# Conteo físico en borrador (spec 034): lo contado por producto, que se confirma como ajustes de stock.
class StockCount < ApplicationRecord
  belongs_to :company
  belongs_to :user
  belongs_to :confirmed_by, class_name: "User", optional: true
  has_many :items, class_name: "StockCountItem", dependent: :destroy

  enum :status, { draft: 0, confirmed: 1, discarded: 2 }, default: :draft

  scope :recent, -> { order(created_at: :desc, id: :desc) }
end
