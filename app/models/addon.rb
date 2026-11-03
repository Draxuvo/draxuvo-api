# Catálogo de módulos extra en código, sin tabla (spec 050, como Plan). Un extra no viene en ningún plan:
# se contrata aparte y se cobra como un renglón más de la suscripción. Los nombres visibles salen de i18n
# (modules.<key>); aquí no se guardan textos.
Addon = Data.define(:key, :requires, :monthly_amount_cents) do
  self::LOOKUP_KEY_FORMAT = /\Adraxuvo_addon_([a-z_]+)_(monthly|annual)\z/

  class << self
    def all = self::CATALOG.values

    def keys = self::CATALOG.keys

    def key?(value) = self::CATALOG.key?(value.to_s.to_sym)

    def find(key) = self::CATALOG.fetch(key.to_s.to_sym)

    # Devuelve [addon_key, cycle] a partir de un lookup_key de Stripe, o nil si no es de un extra conocido.
    def parse_lookup_key(value)
      match = self::LOOKUP_KEY_FORMAT.match(value.to_s)
      return unless match && key?(match[1])

      [ match[1].to_sym, match[2].to_sym ]
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
    raise ArgumentError, "unknown billing cycle: #{cycle.inspect}" unless Plan::CYCLES.include?(cycle.to_sym)

    "draxuvo_addon_#{key}_#{cycle}"
  end
end

Addon::CATALOG = [
  Addon.new(key: :pos, requires: %i[inventory].freeze, monthly_amount_cents: 19_900)
].index_by(&:key).freeze

Addon::KEYS = Addon.keys.freeze
