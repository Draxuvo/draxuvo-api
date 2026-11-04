require "test_helper"

class CheckItemTest < ActiveSupport::TestCase
  setup { @check = checks(:open_check) }

  def item(**attrs)
    @check.check_items.create!({ company: @check.company, name: "Plato", unit_price: 10, quantity: 1 }.merge(attrs))
  end

  test "starts as a draft" do
    assert item.status_draft?
  end

  test "quantity must be a positive integer" do
    assert_not @check.check_items.build(company: @check.company, name: "x", quantity: 0).valid?
    assert_not @check.check_items.build(company: @check.company, name: "x", quantity: 1.5).valid?
  end

  test "moves only forward one step at a time" do
    draft = item
    assert_not draft.update(status: :ready), "no se salta de draft a ready"
    assert draft.update(status: :new)
    assert draft.update(status: :preparing)
    assert_not draft.update(status: :new), "no retrocede"
    assert draft.update(status: :ready)
    assert draft.update(status: :delivered)
    assert_not draft.update(status: :cancelled), "un entregado no se cancela"
  end

  test "cancelling something sent needs a reason and who cancelled" do
    sent = check_items(:item_new)

    assert_not sent.update(status: :cancelled)
    assert sent.update(status: :cancelled, cancel_reason: "El cliente cambió", cancelled_by: users(:resto_owner))
  end

  test "a draft cannot be cancelled, it is deleted" do
    assert_not check_items(:item_draft).update(status: :cancelled)
  end

  test "saving an item recalculates the check total" do
    @check.recalculate_total!
    before = @check.reload.total
    item(unit_price: 40, quantity: 2).update!(status: :new, kitchen_order: kitchen_orders(:first_round))

    assert_equal before + 80, @check.reload.total
  end

  test "counted leaves out drafts and cancelled items" do
    statuses = @check.check_items.counted.map(&:status).uniq

    assert_empty statuses & %w[draft cancelled]
  end

  # Spec 054 (H-47): la nota del renglón tiene tope de 200 y solo se exige cuando cambia.
  test "note has a maximum length of 200 that accepts the limit and rejects one more" do
    assert @check.check_items.build(company: @check.company, name: "x", quantity: 1, unit_price: 1, note: "x" * 200).valid?
    long = @check.check_items.build(company: @check.company, name: "x", quantity: 1, unit_price: 1, note: "x" * 201)
    assert_not long.valid?
    assert_includes long.errors.attribute_names, :note
  end

  test "an old item with a longer note can still move forward" do
    record = item
    record.update_columns(note: "y" * 500)
    assert record.reload.update(status: :new), record.errors.full_messages.to_sentence
  end
end
