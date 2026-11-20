require "test_helper"

class Api::V1::Restaurant::ChecksControllerTest < ActionDispatch::IntegrationTest
  setup { @company = companies(:resto_co) }

  def headers_for(user) = auth_headers(user, @company)

  test "opens a check on a free table, at the caller's name" do
    assert_difference -> { Check.count }, 1 do
      post "/api/v1/restaurant/checks", params: { dining_table_id: dining_tables(:table_3).id },
                                        headers: headers_for(users(:resto_waiter)), as: :json
    end

    assert_response :created
    body = response.parsed_body
    assert_equal "open", body["status"]
    assert_equal "3", body.dig("table", "name")
    assert_equal users(:resto_waiter).id, body.dig("waiter", "id")
    assert_empty body["items"]
  end

  test "an occupied table answers 422 table_occupied" do
    post "/api/v1/restaurant/checks", params: { dining_table_id: dining_tables(:table_1).id },
                                      headers: headers_for(users(:resto_waiter2)), as: :json

    assert_response :unprocessable_entity
    assert_equal "table_occupied", response.parsed_body.dig("error", "details", "code")
  end

  test "opens a takeout check with a name" do
    post "/api/v1/restaurant/checks", params: { takeout_name: "María" }, headers: headers_for(users(:resto_waiter)), as: :json

    assert_response :created
    assert_equal "María", response.parsed_body["takeout_name"]
    assert_nil response.parsed_body["table"]
  end

  test "a takeout check without a name is invalid" do
    post "/api/v1/restaurant/checks", params: { takeout_name: " " }, headers: headers_for(users(:resto_waiter)), as: :json

    assert_response :unprocessable_entity
  end

  test "a table of another company is not found" do
    foreign = companies(:pro_co).dining_tables.create!(name: "X")
    post "/api/v1/restaurant/checks", params: { dining_table_id: foreign.id }, headers: headers_for(users(:resto_waiter)), as: :json

    assert_response :not_found
  end

  test "shows the check with items, statuses and actions" do
    get "/api/v1/restaurant/checks/#{checks(:open_check).id}", headers: headers_for(users(:resto_waiter))

    assert_response :ok
    body = response.parsed_body
    assert_equal "155.00", body["total"]
    assert_equal %w[draft new preparing ready], body["items"].map { |i| i["status"] }.sort_by { |s| %w[draft new preparing ready].index(s) }
    assert_includes body["allowed_actions"], "pay"
    ready = body["items"].find { |i| i["status"] == "ready" }
    assert_equal %w[deliver], ready["allowed_actions"], "cancelar algo listo es del encargado"
  end

  test "another waiter does not get the pay action" do
    get "/api/v1/restaurant/checks/#{checks(:open_check).id}", headers: headers_for(users(:resto_waiter2))

    assert_not_includes response.parsed_body["allowed_actions"], "pay"
    assert_includes response.parsed_body["allowed_actions"], "add_item"
  end

  test "a check of another company is not found" do
    get "/api/v1/restaurant/checks/#{checks(:open_check).id}",
        headers: auth_headers(users(:pro_co_owner), companies(:pro_co))

    assert_response :not_found
  end

  test "a boss reassigns the waiter" do
    patch "/api/v1/restaurant/checks/#{checks(:open_check).id}", params: { waiter_id: users(:resto_waiter2).id },
                                                                 headers: headers_for(users(:resto_owner)), as: :json

    assert_response :ok
    assert_equal users(:resto_waiter2), checks(:open_check).reload.waiter
  end

  test "a waiter cannot reassign" do
    patch "/api/v1/restaurant/checks/#{checks(:open_check).id}", params: { waiter_id: users(:resto_waiter2).id },
                                                                 headers: headers_for(users(:resto_waiter)), as: :json

    assert_response :forbidden
  end

  test "reassigning to someone outside the company is rejected" do
    patch "/api/v1/restaurant/checks/#{checks(:open_check).id}", params: { waiter_id: users(:pro_staff).id },
                                                                 headers: headers_for(users(:resto_owner)), as: :json

    assert_response :unprocessable_entity
    assert_equal "waiter_not_member", response.parsed_body.dig("error", "details", "code")
  end

  test "cancels an empty check and frees the table" do
    check = @company.checks.create!(dining_table: dining_tables(:table_4), opened_by: users(:resto_waiter),
                                    waiter: users(:resto_waiter), opened_at: Time.current)
    post "/api/v1/restaurant/checks/#{check.id}/cancel", headers: headers_for(users(:resto_waiter)), as: :json

    assert_response :ok
    assert_equal "cancelled", response.parsed_body["status"]
    assert_not dining_tables(:table_4).occupied?
  end

  test "a check with sent items cannot be cancelled" do
    post "/api/v1/restaurant/checks/#{checks(:open_check).id}/cancel", headers: headers_for(users(:resto_owner)), as: :json

    assert_response :unprocessable_entity
    assert_equal "has_sent_items", response.parsed_body.dig("error", "details", "code")
  end

  test "a check whose sent items are all cancelled can be released, and its items are kept" do
    check = @company.checks.create!(dining_table: dining_tables(:table_4), opened_by: users(:resto_waiter),
                                    waiter: users(:resto_waiter), opened_at: Time.current)
    item = check.check_items.create!(company: @company, product: products(:resto_agua), name: "Agua", unit_price: 25, quantity: 1)
    item.update_columns(status: CheckItem.statuses[:cancelled], cancelled_at: Time.current, cancel_reason: "N")

    get "/api/v1/restaurant/checks/#{check.id}", headers: headers_for(users(:resto_owner))
    assert_includes response.parsed_body["allowed_actions"], "cancel"

    post "/api/v1/restaurant/checks/#{check.id}/cancel", headers: headers_for(users(:resto_owner)), params: { reason: "Prueba" }, as: :json

    assert_response :ok
    assert_equal "cancelled", response.parsed_body["status"]
    assert_equal 1, check.check_items.reload.count
    assert_not dining_tables(:table_4).occupied?
  end

  test "another waiter cannot cancel an empty check that is not theirs" do
    post "/api/v1/restaurant/checks/#{checks(:takeout_check).id}/cancel", headers: headers_for(users(:resto_waiter)), as: :json

    assert_response :forbidden
  end

  test "drafts are discarded when an otherwise empty check is cancelled" do
    check = checks(:takeout_check)
    check.check_items.create!(company: @company, product: products(:resto_agua), name: "Agua", unit_price: 25, quantity: 1)
    post "/api/v1/restaurant/checks/#{check.id}/cancel", headers: headers_for(users(:resto_waiter2)), as: :json

    assert_response :ok
    assert_equal 0, check.check_items.count
  end

  test "items carry the product id and its icons" do
    products(:resto_tacos).update!(icon: "taco")
    products(:resto_tacos).product_type.update!(icon: "utensils")

    get "/api/v1/restaurant/checks/#{checks(:open_check).id}", headers: headers_for(users(:resto_waiter))

    taco = response.parsed_body["items"].find { |i| i["name"] == "Tacos al pastor" }
    assert_equal products(:resto_tacos).id, taco["product_id"]
    assert_equal "taco", taco["icon"]
    assert_equal "utensils", taco["type_icon"]
  end

  # Spec 070: las cuentas canceladas se listan para el filtro «Canceladas».
  def cancelled_check(waiter:, table: nil, takeout_name: nil, at: 1.hour.ago, reason: nil, by: nil)
    @company.checks.create!(dining_table: table, takeout_name: takeout_name, opened_by: waiter, waiter: waiter,
                            opened_at: at - 10.minutes, closed_at: at, status: :cancelled, cancel_reason: reason,
                            cancelled_by: by)
  end

  def list_cancelled(user, **params)
    get "/api/v1/restaurant/checks", params: { status: "cancelled" }.merge(params), headers: headers_for(user)
  end

  test "a boss lists the cancelled checks, newest first, without open or closed ones" do
    older = cancelled_check(waiter: users(:resto_waiter), table: dining_tables(:table_4), at: 2.hours.ago)
    newer = cancelled_check(waiter: users(:resto_waiter2), takeout_name: "Rosa", at: 30.minutes.ago,
                            reason: "Se fue", by: users(:resto_owner))

    list_cancelled(users(:resto_owner))

    assert_response :ok
    body = response.parsed_body
    assert_equal [ newer.id, older.id ], body["results"].map { |c| c["id"] }
    assert_equal 2, body.dig("info", "total")
    first = body["results"].first
    assert_nil first["table"]
    assert_equal "Rosa", first["takeout_name"]
    assert_equal "Se fue", first["cancel_reason"]
    assert_equal users(:resto_owner).id, first.dig("cancelled_by", "id")
    assert_equal users(:resto_waiter2).id, first.dig("waiter", "id")
    assert_not first["mine"]
    assert first["cancelled_at"].present?
    assert first["opened_at"].present?
    assert_equal "4", body["results"].last.dig("table", "name")
    assert_nil body["results"].last["cancelled_by"]
  end

  test "each cancelled check carries how many items were cancelled" do
    check = @company.checks.create!(dining_table: dining_tables(:table_4), opened_by: users(:resto_waiter),
                                    waiter: users(:resto_waiter), opened_at: Time.current)
    2.times do
      item = check.check_items.create!(company: @company, product: products(:resto_agua), name: "Agua", unit_price: 25, quantity: 1)
      item.update_columns(status: CheckItem.statuses[:cancelled], cancelled_at: Time.current, cancel_reason: "N")
    end
    check.update_columns(status: Check.statuses[:cancelled], closed_at: Time.current)

    list_cancelled(users(:resto_owner))

    assert_equal 2, response.parsed_body["results"].find { |c| c["id"] == check.id }["cancelled_items"]
  end

  test "staff only see the cancelled checks they waited, even asking for another waiter" do
    mine = cancelled_check(waiter: users(:resto_waiter), table: dining_tables(:table_4))
    cancelled_check(waiter: users(:resto_waiter2), takeout_name: "Otro")

    list_cancelled(users(:resto_waiter), waiter_id: users(:resto_waiter2).id)

    assert_response :ok
    assert_equal [ mine.id ], response.parsed_body["results"].map { |c| c["id"] }
    assert response.parsed_body["results"].first["mine"]
  end

  test "a boss filters the cancelled checks by waiter" do
    cancelled_check(waiter: users(:resto_waiter), table: dining_tables(:table_4))
    theirs = cancelled_check(waiter: users(:resto_waiter2), takeout_name: "Otro")

    list_cancelled(users(:resto_owner), waiter_id: users(:resto_waiter2).id)

    assert_equal [ theirs.id ], response.parsed_body["results"].map { |c| c["id"] }
  end

  test "search matches the table, the takeout name and the waiter" do
    table = cancelled_check(waiter: users(:resto_waiter), table: dining_tables(:table_4))
    takeout = cancelled_check(waiter: users(:resto_waiter), takeout_name: "Rosa Pérez")
    waiter = cancelled_check(waiter: users(:resto_waiter2), takeout_name: "Juan")

    list_cancelled(users(:resto_owner), search: "4")
    assert_includes response.parsed_body["results"].map { |c| c["id"] }, table.id

    list_cancelled(users(:resto_owner), search: "rosa")
    assert_equal [ takeout.id ], response.parsed_body["results"].map { |c| c["id"] }

    list_cancelled(users(:resto_owner), search: "waiter2")
    assert_equal [ waiter.id ], response.parsed_body["results"].map { |c| c["id"] }
  end

  test "the cancelled list is paginated" do
    3.times { |i| cancelled_check(waiter: users(:resto_waiter), takeout_name: "T#{i}", at: (i + 1).hours.ago) }

    list_cancelled(users(:resto_owner), page_size: 2)

    assert_equal 2, response.parsed_body["results"].size
    assert_equal 3, response.parsed_body.dig("info", "total")
  end

  test "listing checks needs status=cancelled" do
    get "/api/v1/restaurant/checks", headers: headers_for(users(:resto_owner))
    assert_response :unprocessable_entity

    list_cancelled(users(:resto_owner), status: "closed")
    assert_response :unprocessable_entity
  end

  test "cancelled checks of another company are not listed" do
    cancelled_check(waiter: users(:resto_waiter), takeout_name: "Mía")

    get "/api/v1/restaurant/checks", params: { status: "cancelled" },
                                     headers: auth_headers(users(:pro_co_owner), companies(:pro_co))

    assert_response :ok
    assert_empty response.parsed_body["results"]
  end

  test "a company without the restaurant module cannot list cancelled checks" do
    @company.update!(disabled_modules: [ "restaurant" ])
    list_cancelled(users(:resto_owner))

    assert_response :forbidden
    assert_equal "module_not_in_plan", response.parsed_body.dig("error", "details", "code")
  end

  test "releasing a table records who cancelled the check" do
    check = @company.checks.create!(dining_table: dining_tables(:table_4), opened_by: users(:resto_waiter),
                                    waiter: users(:resto_waiter), opened_at: Time.current)
    post "/api/v1/restaurant/checks/#{check.id}/cancel", headers: headers_for(users(:resto_owner)),
                                                          params: { reason: "Se fueron" }, as: :json

    assert_response :ok
    assert_equal users(:resto_owner), check.reload.cancelled_by
    assert_equal users(:resto_owner).id, response.parsed_body.dig("cancelled_by", "id")
    assert_equal "Se fueron", response.parsed_body["cancel_reason"]
    assert response.parsed_body["closed_at"].present?
  end

  test "a cancelled check shows its cancellation and its cancelled items, without actions" do
    check = @company.checks.create!(dining_table: dining_tables(:table_4), opened_by: users(:resto_waiter),
                                    waiter: users(:resto_waiter), opened_at: Time.current)
    item = check.check_items.create!(company: @company, product: products(:resto_agua), name: "Agua", unit_price: 25, quantity: 1)
    item.update_columns(status: CheckItem.statuses[:cancelled], cancelled_at: Time.current, cancel_reason: "Error",
                        cancelled_by_id: users(:resto_waiter).id)
    post "/api/v1/restaurant/checks/#{check.id}/cancel", headers: headers_for(users(:resto_owner)), as: :json

    get "/api/v1/restaurant/checks/#{check.id}", headers: headers_for(users(:resto_owner))

    body = response.parsed_body
    assert_equal "cancelled", body["status"]
    assert_empty body["allowed_actions"]
    line = body["items"].first
    assert_equal "Error", line["cancel_reason"]
    assert_equal users(:resto_waiter).id, line.dig("cancelled_by", "id")
    assert line["cancelled_at"].present?
  end
end
