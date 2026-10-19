# Catálogo de planes en código, sin tabla (research R8, data-model "Plan").
# Los nombres visibles salen de i18n (plans.<key>); aquí no se guardan textos.
Plan = Data.define(:key, :modules, :monthly_amount_cents) do
  self::MODULES = %i[employees attendance inventory work_orders tickets reports restaurant whatsapp multi_company].freeze
  self::CYCLES = %i[monthly annual].freeze
  self::LOOKUP_KEY_FORMAT = /\Adraxuvo_(basic|pro|enterprise)_(monthly|annual)\z/

  class << self
    def all = self::CATALOG.values

    def keys = self::CATALOG.keys

    def find(key) = self::CATALOG.fetch(key.to_sym)

    # Devuelve [plan_key, cycle] a partir de un lookup_key de Stripe (R9), o nil.
    def parse_lookup_key(value)
      match = self::LOOKUP_KEY_FORMAT.match(value.to_s)
      match && [ match[1].to_sym, match[2].to_sym ]
    end
  end

  def annual_amount_cents = monthly_amount_cents * 10

  def amount_cents(cycle)
    case cycle.to_sym
    when :monthly then monthly_amount_cents
    when :annual then annual_amount_cents
    else raise ArgumentError, "unknown billing cycle: #{cycle.inspect}"
    end
  end

  def lookup_key(cycle)
    raise ArgumentError, "unknown billing cycle: #{cycle.inspect}" unless self.class::CYCLES.include?(cycle.to_sym)

    "draxuvo_#{key}_#{cycle}"
  end

  def includes?(module_key) = modules.include?(module_key.to_sym)
end

Plan::CATALOG = [
  Plan.new(key: :basic, monthly_amount_cents: 39_900,
           modules: %i[employees attendance inventory].freeze),
  Plan.new(key: :pro, monthly_amount_cents: 70_000,
           modules: %i[employees attendance inventory work_orders tickets reports restaurant].freeze),
  Plan.new(key: :enterprise, monthly_amount_cents: 129_900,
           modules: Plan::MODULES)
].index_by(&:key).freeze
