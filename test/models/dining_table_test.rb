require "test_helper"

class DiningTableTest < ActiveSupport::TestCase
  test "a table is occupied while it has an open check" do
    assert dining_tables(:table_1).occupied?
    assert_not dining_tables(:table_2).occupied?, "su cuenta está cerrada"
    assert_not dining_tables(:table_3).occupied?
  end

  test "names are unique per company" do
    assert_not companies(:resto_co).dining_tables.build(name: "1").valid?
    assert companies(:pro_co).dining_tables.build(name: "1").valid?
  end

  # Spec 054 (H-47): el nombre tiene tope de 100 y solo se exige cuando cambia.
  test "name has a maximum length of 100 that accepts the limit and rejects one more" do
    assert DiningTable.new(company: companies(:resto_co), name: "x" * 100).valid?
    record = DiningTable.new(company: companies(:resto_co), name: "x" * 101)
    assert_not record.valid?
    assert_includes record.errors.attribute_names, :name
  end

  test "an old record with a longer name can still be updated without touching the name" do
    record = DiningTable.new(company: companies(:resto_co), name: "Corto")
    record.save!
    record.update_columns(name: "y" * 300)
    assert record.reload.update(position: 3) if record.respond_to?(:position=)
    assert_not record.update(name: "z" * 300)
  end

  # Spec 059: enlace público del menú.
  test "ensure_menu_token! creates a 22-character URL-safe token once" do
    table = dining_tables(:table_1)
    assert_nil table.menu_token

    token = table.ensure_menu_token!
    assert_match(/\A[A-Za-z0-9_-]{22}\z/, token)
    assert_not_nil table.reload.menu_token_generated_at
    assert_equal token, table.ensure_menu_token!, "es idempotente"
    assert_equal token, table.reload.menu_token
  end

  test "regenerate_menu_token! always replaces the token and its date" do
    table = dining_tables(:table_1)
    old = table.ensure_menu_token!
    table.update_columns(menu_token_generated_at: 2.days.ago)

    fresh = table.regenerate_menu_token!
    assert_not_equal old, fresh
    assert_in_delta Time.current, table.reload.menu_token_generated_at, 5
    assert_empty DiningTable.with_menu_token(old)
    assert_equal [ table ], DiningTable.with_menu_token(fresh).to_a
  end

  test "two tables never share a token" do
    tokens = (1..4).map { |n| dining_tables(:"table_#{n}").ensure_menu_token! }
    assert_equal 4, tokens.uniq.size
    assert_raises(ActiveRecord::RecordNotUnique) { dining_tables(:table_2).update_columns(menu_token: tokens.first) }
  end

  test "with_menu_token finds nothing for blank tokens" do
    dining_tables(:table_1).ensure_menu_token!
    assert_empty DiningTable.with_menu_token(nil)
    assert_empty DiningTable.with_menu_token("  ")
  end

  test "menu_url points to the public site and drops the trailing slash" do
    table = dining_tables(:table_1)
    assert_nil table.menu_url

    token = table.ensure_menu_token!
    with_env("PUBLIC_SITE_URL" => "https://draxuvo.com/") do
      assert_equal "https://draxuvo.com/m/#{token}", table.menu_url
    end
    with_env("PUBLIC_SITE_URL" => nil) do
      assert_equal "http://localhost:4300/m/#{token}", table.menu_url
    end
  end
end
