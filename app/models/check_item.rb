# Artículo de una cuenta. Copia el nombre y el precio del producto al agregarlo.
class CheckItem < ApplicationRecord
  STATUSES = { draft: 0, new: 1, preparing: 2, ready: 3, delivered: 4, cancelled: 5 }.freeze
  # De dónde puede venir cada estado: solo hacia adelante, o cancelado desde lo mandado.
  FROM = {
    "new"       => %w[draft],
    "preparing" => %w[new],
    "ready"     => %w[preparing],
    "delivered" => %w[ready],
    "cancelled" => %w[new preparing ready]
  }.freeze

  belongs_to :company
  belongs_to :check
  belongs_to :kitchen_order, optional: true
  belongs_to :product, optional: true
  belongs_to :station, optional: true
  belongs_to :cancelled_by, class_name: "User", optional: true

  enum :status, STATUSES, default: :draft, prefix: true

  validates :name, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }
  validates :cancel_reason, :cancelled_by, presence: true, if: -> { status_cancelled? && kitchen_order_id.present? }
  validate :forward_only, if: :will_save_change_to_status?

  after_save :recalculate_check_total
  after_destroy :recalculate_check_total

  scope :counted, -> { where(status: %i[new preparing ready delivered]) }
  scope :committed, -> { counted }

  def subtotal = (unit_price * quantity).round(2)

  private

  def forward_only
    from = status_in_database
    return if new_record? && status_draft?
    return if FROM.fetch(status, []).include?(from.to_s)

    errors.add(:status, I18n.t("restaurant.errors.invalid_transition"))
  end

  def recalculate_check_total
    check.recalculate_total! if check && !check.destroyed?
  end
end
