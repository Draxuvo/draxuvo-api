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

  # Sucursales del plan Empresa (R17): un solo nivel. Si la principal se borra, las sucursales
  # se quedan sin billing_company y quedan bloqueadas, sin borrar sus datos (FR-029).
  belongs_to :parent, class_name: "Company", foreign_key: :parent_company_id, optional: true, inverse_of: :branches
  has_many :branches, class_name: "Company", foreign_key: :parent_company_id, inverse_of: :parent

  MAX_COMPANIES_PER_ACCOUNT = 3

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validate :disabled_modules_in_catalog
  validate :one_level_of_branches

  before_validation :generate_slug, on: :create
  after_create :create_trial_subscription, unless: :branch?

  def branch?
    parent_company_id.present?
  end

  # Empresa que paga y define el plan: la principal, o la propia si no es sucursal.
  # nil si la principal de una sucursal ya no existe.
  def billing_company
    branch? ? parent : self
  end

  def billing_subscription
    billing_company&.subscription
  end

  # Módulos del plan de la suscripción de billing_company (R13, R17). Sin suscripción no hay módulos.
  def available_modules
    plan = billing_subscription&.plan
    return [] unless plan

    Plan.find(plan).modules.to_a
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

  def one_level_of_branches
    return unless parent

    errors.add(:parent_company_id, :invalid) if parent.branch? || parent_company_id == id
  end

  def create_trial_subscription
    Subscription.start_trial!(self, plan: :pro)
  end
end
