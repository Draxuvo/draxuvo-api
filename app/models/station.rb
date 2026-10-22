# Lugar donde se prepara una parte de la comanda (cocina, barra). Una por empresa es la predeterminada.
class Station < ApplicationRecord
  belongs_to :company
  has_many :check_items, dependent: :nullify
  has_many :products, dependent: :nullify

  KINDS = %w[kitchen bar other].freeze

  validates :name, presence: true, uniqueness: { scope: :company_id }
  validates :kind, inclusion: { in: KINDS }
  validate :default_station_stays_active

  before_validation :first_station_is_default, on: :create
  after_save :demote_other_defaults, if: :is_default?

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  def self.default_for(company)
    company.stations.active.find_by(is_default: true) || company.stations.active.ordered.first
  end

  private

  def first_station_is_default
    self.is_default = true if company && !company.stations.exists?
  end

  def default_station_stays_active
    errors.add(:base, I18n.t("restaurant.errors.default_station")) if is_default? && !active?
  end

  def demote_other_defaults
    company.stations.where.not(id: id).where(is_default: true).update_all(is_default: false)
  end
end
