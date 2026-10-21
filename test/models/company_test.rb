require "test_helper"

# T017 · R13, R16, data-model.md (Company). Activos = módulos del plan menos disabled_modules.
class CompanyTest < ActiveSupport::TestCase
  BASIC_MODULES = %i[employees attendance inventory].freeze
  PRO_MODULES = (BASIC_MODULES + %i[work_orders tickets reports restaurant terminals]).freeze
  ENTERPRISE_MODULES = (PRO_MODULES + %i[whatsapp multi_company]).freeze

  def assert_same_modules(expected, actual)
    assert_equal expected.map(&:to_sym).sort, actual.map(&:to_sym).sort
  end

  test "disabled_modules es un arreglo vacío por defecto" do
    assert_equal [], companies(:pro_co).disabled_modules
  end

  test "active_modules es el paquete del plan cuando no hay módulos desactivados" do
    assert_same_modules BASIC_MODULES, companies(:basic_co).active_modules
    assert_same_modules PRO_MODULES, companies(:pro_co).active_modules
    assert_same_modules ENTERPRISE_MODULES, companies(:enterprise_co).active_modules
  end

  test "active_modules resta los disabled_modules del plan" do
    company = companies(:pro_co)
    company.update!(disabled_modules: %w[inventory tickets])

    assert_same_modules PRO_MODULES - %i[inventory tickets], company.reload.active_modules
    assert company.module_active?(:work_orders)
    assert_not company.module_active?(:inventory)
  end

  test "un módulo fuera del plan no está activo" do
    company = companies(:basic_co)

    assert_not_includes company.active_modules.map(&:to_sym), :work_orders
    assert_not company.module_active?(:whatsapp)
  end

  test "available_modules no depende de disabled_modules" do
    company = companies(:pro_co)
    company.update!(disabled_modules: %w[reports])

    assert_same_modules PRO_MODULES, company.reload.available_modules
  end

  test "subir de plan prende todo lo nuevo sin escribir en disabled_modules" do
    company = companies(:basic_co)
    company.update!(disabled_modules: %w[attendance])

    company.subscription.update!(plan: :enterprise)

    assert_same_modules ENTERPRISE_MODULES - %i[attendance], company.reload.active_modules
    assert_equal %w[attendance], company.disabled_modules
  end

  test "un desactivado que salió del plan al bajar se conserva sin efecto" do
    company = companies(:enterprise_co)
    company.update!(disabled_modules: %w[whatsapp])

    company.subscription.update!(plan: :basic)

    assert_same_modules BASIC_MODULES, company.reload.active_modules
    assert_equal %w[whatsapp], company.disabled_modules
  end

  test "sin suscripción no hay módulos activos" do
    company = companies(:pro_co)
    company.subscription.destroy!

    assert_equal [], company.reload.active_modules
  end

  test "disabled_modules solo acepta módulos del catálogo" do
    company = companies(:pro_co)
    company.disabled_modules = %w[inventory teleport]

    assert_not company.valid?
    assert company.errors.key?(:disabled_modules)
  end

  test "disabled_modules no acepta duplicados" do
    company = companies(:pro_co)
    company.disabled_modules = %w[inventory inventory]

    assert_not company.valid?
    assert company.errors.key?(:disabled_modules)
  end

  test "una empresa creada por el super admin empieza en prueba Pro" do
    company = Company.create!(name: "Nueva Empresa Admin")
    subscription = company.subscription

    assert_not_nil subscription
    assert subscription.trialing?
    assert_equal "pro", subscription.plan
    assert_equal "monthly", subscription.billing_cycle
    assert_equal 0, subscription.amount_cents
    assert_in_delta 30.days.from_now, subscription.trial_ends_at, 1.minute
    assert subscription.active_access?
    assert_same_modules PRO_MODULES, company.active_modules
  end

  test "Company ya no tiene columna plan; la fuente es la suscripción" do
    assert_not Company.column_names.include?("plan")
  end

  test "order_mode es service por defecto y una sucursal nueva hereda el de su principal" do
    main = Company.create!(name: "Principal Modo", order_mode: :order)
    assert Company.new(name: "x").order_mode_service?
    branch = Company.create!(name: "Sucursal Modo", parent: main)
    assert branch.order_mode_order?
    branch.update!(order_mode: :service)
    assert branch.reload.order_mode_service?
    assert main.reload.order_mode_order?
  end

  test "terminals is a module of Pro and Enterprise and not of Basic" do
    assert companies(:pro_co).module_active?(:terminals)
    assert companies(:enterprise_co).module_active?(:terminals)
    assert_not companies(:basic_co).module_active?(:terminals)
  end

  test "bajar a Básico y volver a Pro conserva las terminales y sus pagos" do
    company = companies(:pro_co)
    names = company.payment_terminals.pluck(:name).sort
    payments = TicketPayment.where.not(terminal_id: nil).count

    company.subscription.update!(plan: :basic)
    assert_not company.reload.module_active?(:terminals)
    assert_equal names, company.payment_terminals.pluck(:name).sort

    company.subscription.update!(plan: :pro)
    assert company.reload.module_active?(:terminals)
    assert_equal names, company.payment_terminals.pluck(:name).sort
    assert_equal payments, TicketPayment.where.not(terminal_id: nil).count
  end
end
