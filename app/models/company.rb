# app/models/company.rb
class Company < ApplicationRecord
  has_many :user_companies, dependent: :destroy
  has_many :users, through: :user_companies
  has_many :attendances, dependent: :destroy
  has_many :employees, dependent: :destroy
  has_many :products, dependent: :destroy
  has_many :product_barcodes, dependent: :destroy
  has_many :product_imports, dependent: :destroy
  has_many :stock_counts, dependent: :destroy
  has_many :label_formats, dependent: :destroy
  has_many :stock_movements, dependent: :destroy
  has_many :work_orders, dependent: :destroy
  has_many :tickets, dependent: :destroy
  has_many :stations, dependent: :destroy
  has_many :dining_tables, dependent: :destroy
  has_many :checks, dependent: :destroy
  has_many :sales, dependent: :destroy
  has_many :payment_terminals, dependent: :destroy
  has_many :product_types, dependent: :destroy
  has_many :module_changes, dependent: :destroy
  has_many :payroll_runs, dependent: :destroy
  has_many :payroll_payments, dependent: :destroy
  has_many :payroll_adjustments, dependent: :destroy
  has_many :payroll_events, dependent: :delete_all
  # Spec 045: alertas operativas. Son datos propios de la empresa; se borran con ella (y con la purga de una demo).
  has_one :alert_setting, dependent: :delete
  has_many :alert_snoozes, dependent: :delete_all
  has_many :notification_preferences, dependent: :delete_all
  has_many :stock_alert_states, dependent: :delete_all
  has_many :alert_deliveries, dependent: :delete_all
  has_one :subscription, dependent: :destroy
  # Spec 039: la apertura de demo de esta empresa (solo la principal la tiene; la sucursal usa la de su principal).
  has_one :own_demo_session, class_name: "DemoSession", dependent: :nullify

  # Sucursales del plan Empresa (R17): un solo nivel. Si la principal se borra, las sucursales
  # se quedan sin billing_company y quedan bloqueadas, sin borrar sus datos (FR-029).
  belongs_to :parent, class_name: "Company", foreign_key: :parent_company_id, optional: true, inverse_of: :branches
  has_many :branches, class_name: "Company", foreign_key: :parent_company_id, inverse_of: :parent

  # Modo de órdenes (007): servicio (checklist de pasos) o pedido (entrega y cobro).
  enum :order_mode, { service: 0, order: 1 }, default: :service, prefix: true

  MAX_COMPANIES_PER_ACCOUNT = 3

  # Spec 055 (H-58): el nombre cabe en el selector de empresa. El tope solo se exige cuando el nombre cambia, para no
  # bloquear la edición de empresas que ya tengan uno más largo.
  NAME_MAX_LENGTH = 120

  validates :name, presence: true
  validates :name, length: { maximum: NAME_MAX_LENGTH }, if: :will_save_change_to_name?
  # El slug lo genera la API: sin nombre el aviso ya sale de `name` (spec 055, H-60), y un nombre sin letras ni números
  # (que no produce slug) también se explica sobre el nombre.
  validates :slug, presence: true, if: -> { name.present? && !slug_unavailable_for_name? }
  validates :slug, uniqueness: true, allow_blank: true
  validate :name_produces_slug, on: :create
  validate :disabled_modules_in_catalog
  validate :one_level_of_branches

  before_validation :generate_slug, on: :create
  before_validation :inherit_order_mode, on: :create
  after_create :create_trial_subscription, unless: :branch?
  after_create { ProductTypes::Defaults.create_missing(self) }

  # Spec 039: las empresas de demostración (una por visita) y las reales, para no mezclarlas en lo interno.
  scope :demo, -> { where(demo: true) }
  scope :real, -> { where(demo: false) }

  # Sesión de demo que rige a esta empresa: la propia o, si es una sucursal, la de su principal.
  def demo_session
    return nil unless demo?

    own_demo_session || parent&.own_demo_session
  end

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

  # Módulos del plan de la suscripción de billing_company (R13, R17) más los extras contratados y vigentes
  # (spec 050). Sin suscripción no hay módulos.
  def available_modules
    subscription = billing_subscription
    return [] unless subscription&.plan

    # La asociación se carga una sola vez por suscripción: module_active? se llama muchas veces por petición.
    Plan.find(subscription.plan).modules.to_a | subscription.addons.select(&:current?).map { |addon| addon.module.to_sym }
  end

  # De dónde viene cada módulo disponible: "plan" o "addon".
  def module_sources
    plan_modules = billing_subscription&.plan ? Plan.find(billing_subscription.plan).modules : []
    available_modules.index_with { |key| plan_modules.include?(key) ? "plan" : "addon" }
  end

  # Activos = plan menos disabled_modules (R16). Un desactivado fuera del plan no tiene efecto.
  def active_modules
    available_modules - Array(disabled_modules).map(&:to_sym)
  end

  def module_active?(module_key)
    active_modules.include?(module_key.to_sym)
  end

  private

  # Una sucursal nueva hereda el modo de su principal; después se cambia por separado.
  def inherit_order_mode
    self.order_mode = parent.order_mode if parent
  end

  def generate_slug
    self.slug ||= name.to_s.downcase.gsub(/\s+/, "-").gsub(/[^a-z0-9-]/, "")
  end

  # Un nombre con texto pero sin letras ni números (`"!!!"`) no produce slug.
  def slug_unavailable_for_name?
    slug.blank? && name.to_s.downcase.gsub(/[^a-z0-9]/, "").blank?
  end

  def name_produces_slug
    errors.add(:name, :invalid) if name.present? && slug_unavailable_for_name?
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
