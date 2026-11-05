module Push
  # Catálogo de tipos de aviso push (spec 057, data-model): quién puede recibirlo, qué módulo del plan lo exige y cómo se
  # entrega (canal de Android, prioridad y vigencia en Expo).
  module Kinds
    Kind = Struct.new(:key, :roles, :modules, :channel, :priority, :ttl, keyword_init: true)

    ALL_ROLES = %w[staff admin owner super_admin].freeze
    BOSS_ROLES = %w[admin owner super_admin].freeze

    CATALOG = {
      "check_ready" => Kind.new(key: "check_ready", roles: ALL_ROLES, modules: %i[restaurant], channel: "orders",
                                priority: "high", ttl: 300),
      "work_order_assigned" => Kind.new(key: "work_order_assigned", roles: ALL_ROLES, modules: %i[work_orders], channel: "orders",
                                        priority: "high", ttl: 86_400),
      "operational_alert" => Kind.new(key: "operational_alert", roles: BOSS_ROLES, modules: %i[restaurant work_orders],
                                      channel: "business", priority: "default", ttl: 3600),
      "low_stock" => Kind.new(key: "low_stock", roles: BOSS_ROLES, modules: %i[inventory], channel: "business",
                              priority: "default", ttl: 86_400)
    }.freeze

    module_function

    def fetch(kind) = CATALOG.fetch(kind.to_s)

    # Basta con uno de sus módulos (las alertas operativas valen con restaurante o con órdenes de trabajo).
    def module_active?(kind, company) = fetch(kind).modules.any? { |key| company.module_active?(key) }

    def allowed_role?(kind, role) = fetch(kind).roles.include?(role.to_s)

    # Tipos que puede elegir en «Mis avisos» quien tiene `role` en `company` (FR-006).
    def available_for(role, company)
      CATALOG.keys.select { |kind| allowed_role?(kind, role) && module_active?(kind, company) }
    end
  end
end
