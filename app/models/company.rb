# app/models/company.rb
class Company < ApplicationRecord
  has_many :user_companies, dependent: :destroy
  has_many :users, through: :user_companies
  has_many :attendances, dependent: :destroy
  has_many :employees, dependent: :destroy
  has_many :products, dependent: :destroy
  has_many :stock_movements, dependent: :destroy
  has_many :work_orders, dependent: :destroy
  has_many :tickets, dependent: :destroy
  has_one :subscription, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validate :disabled_modules_in_catalog

  before_validation :generate_slug, on: :create
  after_create :create_trial_subscription

  # Módulos del plan de la suscripción (R13). Sin suscripción no hay módulos.
  def available_modules
    return [] unless subscription&.plan

    Plan.find(subscription.plan).modules.to_a
  end

  # Activos = plan menos disabled_modules (R16). Un desactivado fuera del plan no tiene efecto.
  def active_modules
    available_modules - Array(disabled_modules).map(&:to_sym)
  end

  def module_active?(module_key)
    active_modules.include?(module_key.to_sym)
  end

  private

  def generate_slug
    self.slug ||= name.to_s.downcase.gsub(/\s+/, "-").gsub(/[^a-z0-9-]/, "")
  end

  def disabled_modules_in_catalog
    values = Array(disabled_modules).map(&:to_s)
    unknown = values - Plan::MODULES.map(&:to_s)
    errors.add(:disabled_modules, :inclusion, value: unknown.join(", ")) if unknown.any?
    errors.add(:disabled_modules, :taken) if values.uniq.size != values.size
  end

  def create_trial_subscription
    Subscription.start_trial!(self, plan: :pro)
  end
end
