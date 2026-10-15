require "test_helper"

class JwtHelperTest < ActiveSupport::TestCase
  test "uses 24 hours when the payload has no exp" do
    payload = JwtHelper.jwt_decode(JwtHelper.jwt_encode(user_id: 1))
    assert_in_delta 24.hours.from_now.to_i, payload[:exp], 60
  end

  test "respects an exp inside the payload" do
    exp = 72.hours.from_now.to_i
    assert_equal exp, JwtHelper.jwt_decode(JwtHelper.jwt_encode(user_id: 1, exp: exp))[:exp]
  end

  test "respects the exp passed as an argument" do
    exp = 2.hours.from_now
    assert_equal exp.to_i, JwtHelper.jwt_decode(JwtHelper.jwt_encode({ user_id: 1 }, exp))[:exp]
  end

  test "an expired token raises" do
    token = JwtHelper.jwt_encode({ user_id: 1 }, 1.minute.ago)
    assert_raises(JWT::ExpiredSignature) { JwtHelper.jwt_decode(token) }
  end
end
