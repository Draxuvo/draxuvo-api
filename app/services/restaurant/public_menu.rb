module Restaurant
  # Menú público de una mesa (spec 059): lo que ve el comensal al escanear el QR, sin sesión. La empresa sale solo del
  # token de la mesa (FR-024). Como esta consulta se salta la puerta de suscripción y el contexto de demo de
  # BaseController, aquí se reaplican sus reglas (módulo, suscripción, sucursal, demo), sin crear nunca una prueba.
  #
  # Resultado: `status` :ok, :invalid (token inexistente o mesa desactivada) o :unavailable (la empresa no puede
  # mostrar su menú; el motivo no sale al comensal, FR-020).
  class PublicMenu
    Result = Struct.new(:status, :company, :table, :categories, keyword_init: true) do
      def ok? = status == :ok
    end

    Category = Struct.new(:name, :items, keyword_init: true)
    Item = Struct.new(:product, :sold_out, keyword_init: true)

    def self.call(token) = new(token).call

    def initialize(token)
      @token = token
    end

    def call
      table = DiningTable.with_menu_token(@token).includes(:company).first
      return Result.new(status: :invalid) if table.nil? || !table.active?

      company = table.company
      return Result.new(status: :unavailable) unless available?(company)

      Result.new(status: :ok, company: company, table: table, categories: categories_for(company))
    end

    private

    def available?(company)
      subscription = company.billing_subscription
      return false if subscription.nil? || subscription.suspended? || !subscription.active_access?
      return false if company.branch? && !company.billing_company.available_modules.include?(:multi_company)
      return false unless company.module_active?(:restaurant)
      return false if company.demo? && !company.demo_session&.usable?

      true
    end

    # Mismo orden que Tomar pedido (categoría y nombre); los agotados al final de su categoría (FR-012a).
    def categories_for(company)
      availability = Availability.new(company)
      # Con la foto y sus versiones precargadas (spec 061): saber si está lista y firmar sus URLs sin una consulta por producto.
      Product.menu_for(company).with_photo_variants.group_by(&:category).map do |name, products|
        items = products.map { |product| Item.new(product: product, sold_out: availability.sold_out?(product)) }
        Category.new(name: name || I18n.t("products.menu.uncategorized"), items: items.sort_by { |item| item.sold_out ? 1 : 0 })
      end
    end
  end
end
