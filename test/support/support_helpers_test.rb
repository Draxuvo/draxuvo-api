require "test_helper"

class SupportHelpersTest < ActiveSupport::TestCase
  test "with_env sets a value and restores the previous one" do
    ENV["SUPPORT_HELPER_X"] = "before"
    with_env("SUPPORT_HELPER_X" => "during") { assert_equal "during", ENV["SUPPORT_HELPER_X"] }
    assert_equal "before", ENV["SUPPORT_HELPER_X"]
  ensure
    ENV.delete("SUPPORT_HELPER_X")
  end

  test "with_env unsets variables that did not exist and restores on error" do
    ENV.delete("SUPPORT_HELPER_Y")
    assert_raises(RuntimeError) do
      with_env("SUPPORT_HELPER_Y" => "x") { raise "boom" }
    end
    assert_not ENV.key?("SUPPORT_HELPER_Y")
  end

  test "with_env with nil unsets and then restores" do
    ENV["SUPPORT_HELPER_Z"] = "keep"
    with_env("SUPPORT_HELPER_Z" => nil) { assert_not ENV.key?("SUPPORT_HELPER_Z") }
    assert_equal "keep", ENV["SUPPORT_HELPER_Z"]
  ensure
    ENV.delete("SUPPORT_HELPER_Z")
  end

  test "with_memory_cache swaps Rails.cache and restores it" do
    original = Rails.cache
    with_memory_cache do
      assert_instance_of ActiveSupport::Cache::MemoryStore, Rails.cache
      Rails.cache.write("k", 1)
    end
    assert_same original, Rails.cache
  end

  test "stripe helpers are available" do
    assert_includes self.class.ancestors, StripeHelpers
    assert_equal "sub_1", stripe_sub_hash(id: "sub_1", status: "active", lookup_key: "k")[:id]
  end
end
