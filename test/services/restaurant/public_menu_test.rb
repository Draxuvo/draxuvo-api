require "test_helper"

# Spec 059: menú público de una mesa (token → :ok, :invalid o :unavailable).
class Restaurant::PublicMenuTest < ActiveSupport::TestCase
  setup do
    @company = companies(:resto_co)
    @table = dining_tables(:table_4)
    @token = @table.ensure_menu_token!
  end

  def menu(token = @token) = Restaurant::PublicMenu.call(token)

  def names(result) = result.categories.flat_map { |c| c.items.map { |i| i.product.name } }

  test "a valid token gives the business, the table and the menu by category" do
    result = menu
    assert result.ok?
    assert_equal @company, result.company
    assert_equal @table, result.table
    assert_equal %w[Bebidas Platillos], result.categories.map(&:name)
    assert_equal names(result).sort, Product.menu_for(@company).map(&:name).sort, "los mismos productos que Tomar pedido"
  end

  test "unknown, blank or regenerated tokens and inactive tables are invalid" do
    assert_equal :invalid, menu("no-existe-este-token1").status
    assert_equal :invalid, menu("").status
    assert_equal :invalid, menu(nil).status

    old = @token
    @table.regenerate_menu_token!
    assert_equal :invalid, menu(old).status
    assert menu(@table.menu_token).ok?

    @table.update!(active: false)
    assert_equal :invalid, menu(@table.menu_token).status
  end

  test "products outside the menu, unavailable or not sellable do not appear" do
    product_types(:resto_co_counted).update!(in_menu: false)
    products(:resto_agua).update!(available: false)

    listed = names(menu)
    assert_equal [ "Sopa del día" ], listed
  end

  test "sold out products are flagged and go last in their category" do
    products(:resto_tacos).update_columns(stock: 0)
    @company.products.create!(sku: "QUESA-059", name: "Quesadilla", product_type: product_types(:resto_co_sold),
                              price: 40, category: "Platillos")

    platillos = menu.categories.find { |c| c.name == "Platillos" }
    assert_equal [ "Quesadilla", "Sopa del día", "Tacos al pastor" ], platillos.items.map { |i| i.product.name }
    assert_equal [ false, false, true ], platillos.items.map(&:sold_out)
  end

  test "products without category use the uncategorized label" do
    products(:resto_sopa).update!(category: nil)
    assert_includes menu.categories.map(&:name), I18n.t("products.menu.uncategorized")
  end

  test "without the restaurant module the menu is unavailable" do
    @company.update!(disabled_modules: [ "restaurant" ])
    assert_equal :unavailable, menu.status

    @company.update!(disabled_modules: [])
    assert menu.ok?, "al recuperar el módulo el mismo enlace vuelve a servir (FR-021)"
  end

  test "a plan without restaurant is unavailable" do
    subscriptions(:resto_co).update!(plan: :basic)
    assert_equal :unavailable, menu.status
  end

  test "suspended, expired, cancelled or missing subscriptions are unavailable and never create a trial" do
    subscription = subscriptions(:resto_co)

    %i[suspended cancelled expired].each do |status|
      subscription.update_columns(status: Subscription.statuses.fetch(status))
      assert_equal :unavailable, menu.status, status.to_s
    end

    subscription.update_columns(status: Subscription.statuses[:trialing], trial_ends_at: 1.day.ago)
    assert_equal :unavailable, menu.status, "prueba vencida"

    subscription.update_columns(status: Subscription.statuses[:active])
    assert menu.ok?, "al reactivar la suscripción vuelve a servir (FR-021)"

    subscription.destroy!
    assert_no_difference -> { Subscription.count } do
      assert_equal :unavailable, menu.status
    end
  end

  test "an inactive table becomes valid again when reactivated" do
    @table.update!(active: false)
    assert_equal :invalid, menu.status
    @table.update!(active: true)
    assert menu.ok?
  end

  test "a branch shows its own menu only when the main company has multi_company" do
    branch = Company.create!(name: "Sazón Sucursal", parent: @company)
    branch_table = branch.dining_tables.create!(name: "Terraza 1")
    branch.products.create!(sku: "SUC-059", name: "Pozole", product_type: branch.product_types.find_by(sellable: true, counted: false),
                            price: 90, category: "Platillos")
    token = branch_table.ensure_menu_token!

    assert_equal :unavailable, menu(token).status, "Pro no incluye multi_company"

    subscriptions(:resto_co).update!(plan: :enterprise)
    result = menu(token)
    assert result.ok?
    assert_equal "Sazón Sucursal", result.company.name
    assert_equal [ "Pozole" ], names(result), "nunca el menú de la principal"
    assert_not_includes names(menu), "Pozole", "ni la principal el de la sucursal"
  end

  test "a demo company is unavailable once its demo is no longer usable" do
    @company.update!(demo: true)
    session = DemoSession.create!(company: @company, plan: "pro", scenario: Demo::Scenarios.keys.first, locale: "es",
                                  expires_at: 1.hour.from_now)
    assert menu.ok?

    session.update!(expires_at: 1.minute.ago)
    assert_equal :unavailable, menu.status
  end
end
