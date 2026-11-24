require "test_helper"

class UserAgentSummaryTest < ActiveSupport::TestCase
  CASES = {
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" => "Chrome · macOS",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1" => "Safari · iOS",
    "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" => "Safari · iPadOS",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0" => "Edge · Windows",
    "Mozilla/5.0 (X11; Linux x86_64; rv:132.0) Gecko/20100101 Firefox/132.0" => "Firefox · Linux",
    "Mozilla/5.0 (Linux; Android 14; SM-S711B) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/26.0 Chrome/122.0.0.0 Mobile Safari/537.36" => "Samsung Internet · Android",
    "Mozilla/5.0 (Linux; Android 15; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36" => "Chrome · Android",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 OPR/114.0.0.0" => "Opera · Windows",
    "Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" => "Chrome · ChromeOS",
    "okhttp/4.12.0" => "App · Android",
    "Draxuvo/12 CFNetwork/1568.100.1 Darwin/24.0.0" => "App · iOS"
  }.freeze

  test "summarizes common browsers, systems and the native app" do
    CASES.each { |ua, expected| assert_equal expected, UserAgentSummary.call(ua), ua }
  end

  test "unknown or empty user agents" do
    assert_equal "Desconocido", UserAgentSummary.call(nil)
    assert_equal "Desconocido", UserAgentSummary.call("")
    assert_equal "Desconocido", UserAgentSummary.call("curl/8.7.1")
  end

  test "a huge user agent does not break" do
    assert_kind_of String, UserAgentSummary.call("Mozilla/5.0 #{'x' * 2_000}")
  end

  test "detects native app clients" do
    assert UserAgentSummary.native_app?("okhttp/4.12.0")
    assert UserAgentSummary.native_app?("Draxuvo/12 CFNetwork/1568.100.1 Darwin/24.0.0")
    assert_not UserAgentSummary.native_app?(CASES.keys.first)
    assert UserAgentSummary.browser?(CASES.keys.first)
    assert_not UserAgentSummary.browser?("curl/8.7.1")
  end
end
