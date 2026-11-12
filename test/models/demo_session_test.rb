require "test_helper"

class DemoSessionTest < ActiveSupport::TestCase
  def session_expired(ago, failed_at: nil)
    DemoSession.create!(plan: "basic", scenario: "basic_retail", locale: "es", expires_at: ago.ago, purge_failed_at: failed_at)
  end

  # Spec 062: primero las que nunca fallaron (por vencimiento) y al final las que fallaron (la que falló hace más primero).
  test "purge_order puts never-failed sessions first and rotates the failed ones" do
    failed_recently = session_expired(3.hours, failed_at: 1.minute.ago)
    failed_long_ago = session_expired(2.hours, failed_at: 1.hour.ago)
    newer = session_expired(5.minutes)
    older = session_expired(1.hour)

    ids = [ failed_recently, failed_long_ago, newer, older ].map(&:id)
    ordered = DemoSession.purgeable.purge_order.where(id: ids).to_a

    assert_equal [ older, newer, failed_long_ago, failed_recently ], ordered
  end
end
