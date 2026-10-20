# Carga el catálogo inicial de un negocio desde un YAML (db/catalogs/*.yml): modo de órdenes, estaciones,
# mesas, terminales y productos con su inventario inicial. Se puede volver a correr: busca por nombre o SKU,
# actualiza nombre, precio, categoría y estación, y solo registra la entrada de inventario si el producto aún no
# tiene movimientos (así se puede activar el inventario de un producto ya cargado).
module Catalogs
  class Loader
    Result = Struct.new(:company, :created, :updated, :warnings, keyword_init: true)

    def self.call(data, owner_email: nil) = new(data, owner_email: owner_email).call

    def initialize(data, owner_email: nil)
      @data = data.deep_stringify_keys
      @owner_email = owner_email.presence || @data.dig("company", "owner_email")
      @created = Hash.new(0)
      @updated = Hash.new(0)
      @warnings = []
    end

    def call
      company = find_company
      ActiveRecord::Base.transaction do
        company.update!(order_mode: @data["order_mode"]) if @data["order_mode"].present?
        stations = load_stations(company)
        load_tables(company)
        load_terminals(company)
        load_products(company, stations)
      end
      @warnings << "El plan no incluye el módulo de restaurante: las mesas y estaciones no se verán" unless company.module_active?(:restaurant)
      Result.new(company: company, created: @created, updated: @updated, warnings: @warnings)
    end

    private

    # La empresa donde esa persona es dueña; con varias, `company.slug` del YAML decide.
    def find_company
      user = User.find_by!(email: @owner_email.to_s.downcase.strip)
      owned = Company.joins(:user_companies).where(user_companies: { user_id: user.id, role: UserCompany.roles[:owner] })
      slug = @data.dig("company", "slug")
      owned = owned.where(slug: slug) if slug.present?
      raise ArgumentError, "#{@owner_email} es dueño de #{owned.count} empresas; indica company.slug" unless owned.one?

      owned.first
    end

    def load_stations(company)
      Array(@data["stations"]).each_with_index.to_h do |name, index|
        station = company.stations.find_or_initialize_by(name: name)
        count(station) { station.update!(position: index + 1, active: true) }
        [ name, station ]
      end
    end

    def load_tables(company)
      Array(@data["tables"]).each_with_index do |name, index|
        table = company.dining_tables.find_or_initialize_by(name: name.to_s)
        count(table) { table.update!(position: index + 1) }
      end
    end

    def load_terminals(company)
      Array(@data["terminals"]).each do |terminal|
        record = company.payment_terminals.find_or_initialize_by(name: terminal["name"])
        count(record) { record.update!(provider: terminal["provider"]) }
      end
    end

    def load_products(company, stations)
      Array(@data["products"]).each do |item|
        product = company.products.find_or_initialize_by(sku: item.fetch("sku"))
        station = item["station"] && stations.fetch(item["station"]) { raise ArgumentError, "Estación #{item['station']} no está en stations" }
        type = product_type_for(company, product, item)
        count(product) do
          product.update!(
            name: item.fetch("name"), category: item["category"], description: item["description"],
            price: item["price"], unit_cost: item["cost"], station: station, product_type: type, unit_key: item["unit"],
            min_stock: item.fetch("min_stock", 0),
            # "disponible" ya no esconde insumos (spec 016): lo que no se vende queda disponible.
            available: type.sellable ? item.fetch("available", true) : true
          )
        end
        stock = item["stock"].to_d
        next unless stock.positive? && product.stock_movements.none?

        StockMovement.create!(product: product, company: company, movement_type: :entry, qty: stock, note: "Inventario inicial")
      end
    end

    # `type` del YAML por nombre; sin él, la regla de los tipos iniciales con `tracks_stock` y `available` del YAML.
    def product_type_for(company, product, item)
      if item["type"].present?
        return company.product_types.find_by("lower(name) = ?", item["type"].to_s.downcase) ||
               raise(ArgumentError, "Tipo #{item['type']} no existe en la empresa")
      end

      product.tracks_stock = item.fetch("tracks_stock", false)
      product.available = item.fetch("available", true)
      ProductTypes::Defaults.classify(company, product)
    end

    def count(record)
      kind = record.class.model_name.plural
      new_record = record.new_record?
      yield
      (new_record ? @created : @updated)[kind] += 1
    end
  end
end
