require "test_helper"

class Api::V1::PlansControllerTest < ActionDispatch::IntegrationTest
  ALL_MODULES = %w[employees attendance inventory work_orders tickets reports restaurant terminals whatsapp multi_company].freeze

  EXPECTED_PLANS = [
    {
      "key" => "basic",
      "modules" => %w[employees attendance inventory],
      "prices" => {
        "monthly" => { "amount_cents" => 39_900, "iva_cents" => 6_384, "total_cents" => 46_284 },
        "annual" => { "amount_cents" => 399_000, "iva_cents" => 63_840, "total_cents" => 462_840 }
      }
    },
    {
      "key" => "pro",
      "modules" => %w[employees attendance inventory work_orders tickets reports restaurant terminals],
      "prices" => {
        "monthly" => { "amount_cents" => 70_000, "iva_cents" => 11_200, "total_cents" => 81_200 },
        "annual" => { "amount_cents" => 700_000, "iva_cents" => 112_000, "total_cents" => 812_000 }
      }
    },
    {
      "key" => "enterprise",
      "modules" => ALL_MODULES,
      "prices" => {
        "monthly" => { "amount_cents" => 129_900, "iva_cents" => 20_784, "total_cents" => 150_684 },
        "annual" => { "amount_cents" => 1_299_000, "iva_cents" => 207_840, "total_cents" => 1_506_840 }
      }
    }
  ].freeze

  test "GET /plans es público: responde 200 sin Authorization ni X-Company-Id" do
    get "/api/v1/plans"

    assert_response :ok
    assert_equal "application/json", response.media_type
  end

  test "GET /plans responde 200 con un token de una empresa con la prueba vencida" do
    get "/api/v1/plans", headers: auth_headers(users(:expired_co_owner), companies(:expired_co))

    assert_response :ok
  end

  test "GET /plans devuelve iva_rate y el catálogo de módulos" do
    get "/api/v1/plans"

    body = response.parsed_body
    assert_equal 0.16, body["iva_rate"]
    assert_equal ALL_MODULES, body["modules"]
  end

  test "GET /plans devuelve los planes en orden fijo basic, pro, enterprise" do
    get "/api/v1/plans"

    assert_equal %w[basic pro enterprise], response.parsed_body["plans"].map { |p| p["key"] }
  end

  test "GET /plans devuelve módulos, montos sin IVA, IVA y total de cada plan y ciclo" do
    get "/api/v1/plans"

    assert_equal EXPECTED_PLANS, response.parsed_body["plans"]
  end

  test "GET /plans: el anual cuesta 10 veces el mensual y total = monto + IVA" do
    get "/api/v1/plans"

    response.parsed_body["plans"].each do |plan|
      monthly = plan["prices"]["monthly"]
      annual = plan["prices"]["annual"]

      assert_equal monthly["amount_cents"] * 10, annual["amount_cents"], plan["key"]
      [ monthly, annual ].each do |price|
        assert_kind_of Integer, price["iva_cents"]
        assert_equal price["amount_cents"] + price["iva_cents"], price["total_cents"], plan["key"]
      end
    end
  end

  test "GET /plans no expone nombres visibles (los pone el cliente por i18n)" do
    get "/api/v1/plans"

    response.parsed_body["plans"].each do |plan|
      assert_equal %w[key modules prices], plan.keys.sort
    end
  end
end
