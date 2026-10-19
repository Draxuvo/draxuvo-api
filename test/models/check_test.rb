require "test_helper"

class CheckTest < ActiveSupport::TestCase
  setup do
    @company = companies(:resto_co)
    @waiter = users(:resto_waiter)
  end

  def new_check(**attrs)
    @company.checks.new({ opened_by: @waiter, waiter: @waiter, opened_at: Time.current }.merge(attrs))
  end

  test "needs a table or a takeout name" do
    assert_not new_check.valid?
    assert new_check(takeout_name: "Luis").valid?
    assert new_check(dining_table: dining_tables(:table_3)).valid?
  end

  test "the database allows one open check per table" do
    duplicated = new_check(dining_table: dining_tables(:table_1))

    assert_raises(ActiveRecord::RecordNotUnique) { duplicated.save!(validate: false) }
  end

  test "a table of another company is invalid" do
    foreign = companies(:pro_co).dining_tables.create!(name: "X")

    assert_not new_check(dining_table: foreign).valid?
  end

  test "an inactive table cannot take a check" do
    dining_tables(:table_4).update!(active: false)

    assert_not new_check(dining_table: dining_tables(:table_4)).valid?
  end

  test "a closed check is read only" do
    closed = checks(:closed_check)

    assert closed.readonly?
    assert_raises(ActiveRecord::ReadOnlyRecord) { closed.update!(takeout_name: "x") }
  end

  test "an open check can be closed once and is then read only" do
    check = checks(:takeout_check)
    check.update!(status: :closed, closed_at: Time.current)

    assert check.reload.readonly?
  end

  test "total sums the items that count and ignores drafts and cancelled" do
    check = checks(:open_check)
    check.recalculate_total!

    assert_equal 155, check.reload.total, "tacos 70 + sopa 55 + cola 30, sin la horchata sin mandar"
  end

  test "balance is the total minus what was paid" do
    check = checks(:closed_check)

    assert_equal 0, check.balance - (check.total - check.paid_total)
    assert_equal 70, check.paid_total
  end

  test "round numbers are consecutive" do
    assert_equal 2, checks(:open_check).next_round_number
    assert_equal 1, checks(:takeout_check).next_round_number
  end
end
