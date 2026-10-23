require "test_helper"

class Api::V1::BarcodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:resto_co)
    @waiter = auth_headers(users(:resto_waiter), @company)
    @owner = auth_headers(users(:resto_owner), @company)
  end

  def generate(count, headers: @waiter)
    post "/api/v1/barcodes/generate", params: { count: count }, headers: headers, as: :json
  end

  test "reserves the requested number of valid unique codes, defaulting to one" do
    generate(3)
    assert_response :ok
    codes = response.parsed_body["codes"]
    assert_equal 3, codes.uniq.size
    assert(codes.all? { |code| Barcodes::CheckDigit.valid_ean13?(code) })

    post "/api/v1/barcodes/generate", headers: @waiter, as: :json
    assert_equal 1, response.parsed_body["codes"].size
  end

  test "the codes are not assigned to anything and the sequence moves on" do
    assert_no_difference -> { ProductBarcode.count } do
      generate(2)
    end
    first = response.parsed_body["codes"]
    generate(2)

    assert_empty first & response.parsed_body["codes"]
  end

  test "accepts 1 to 100 and rejects anything else" do
    generate(100)
    assert_response :ok

    [ 0, 101, -1, "abc" ].each do |bad|
      generate(bad)
      assert_response :unprocessable_entity
      assert_equal "invalid_count", response.parsed_body.dig("error", "details", "code")
    end
  end

  test "a company with the inventory module turned off is refused" do
    @company.update!(disabled_modules: [ "inventory" ])

    generate(1, headers: @owner)

    assert_response :forbidden
    assert_equal "module_not_in_plan", response.parsed_body.dig("error", "details", "code")
  end
end
