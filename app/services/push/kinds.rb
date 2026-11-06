module Push
  # Catálogo de tipos de aviso push (spec 057, data-model): quién puede recibirlo, qué módulo del plan lo exige y cómo se
  # entrega (canal de Android, prioridad y vigencia en Expo).
  module Kinds
    # `option`: atributo de la empresa que además debe estar encendido (spec 058: «Por cobrar» exige `boss_only_charge`).
    Kind = Struct.new(:key, :roles, :modules, :channel, :priority, :ttl, :option, keyword_init: true)

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
                              priority: "default", ttl: 86_400),
      "charge_pending" => Kind.new(key: "charge_pending", roles: BOSS_ROLES, modules: %i[pos work_orders restaurant],
                                   channel: "business", priority: "high", ttl: 3600, option: :boss_only_charge)
    }.freeze

    module_function

    def fetch(kind) = CATALOG.fetch(kind.to_s)

    # Basta con uno de sus módulos (las alertas operativas valen con restaurante o con órdenes de trabajo).
    # Si el tipo exige una opción de la empresa (`option`), también debe estar encendida.
    def module_active?(kind, company)
      definition = fetch(kind)
      return false if definition.option && !company.public_send(definition.option)

      definition.modules.any? { |key| company.module_active?(key) }
    end

    def allowed_role?(kind, role) = fetch(kind).roles.include?(role.to_s)

    # Tipos que puede elegir en «Mis avisos» quien tiene `role` en `company` (FR-006).
    def available_for(role, company)
      CATALOG.keys.select { |kind| allowed_role?(kind, role) && module_active?(kind, company) }
    end
  end
end
