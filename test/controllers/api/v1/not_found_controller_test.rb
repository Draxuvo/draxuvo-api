require "test_helper"

# Spec 055 (H-61): lo que no existe bajo /api/v1 responde JSON, con o sin sesión.
class Api::V1::NotFoundControllerTest < ActionDispatch::IntegrationTest
  [ [ :delete, "/api/v1/company" ], [ :put, "/api/v1/products" ], [ :delete, "/api/v1/plans" ],
    [ :get, "/api/v1/ruta_que_no_existe" ], [ :post, "/api/v1/a/b/c" ] ].each do |verb, path|
    test "#{verb.upcase} #{path} sin sesión responde 404 en JSON" do
      public_send(verb, path)
      assert_response :not_found
      assert_match(%r{application/json}, response.content_type)
      assert_equal 404, response.parsed_body.dig("error", "status")
      assert_equal "Ruta no encontrada", response.parsed_body.dig("error", "message")
    end
  end

  test "con sesión responde lo mismo" do
    user = User.joins(:user_companies).find_by!(user_companies: { role: :owner })
    delete "/api/v1/company", headers: auth_headers(user)
    assert_response :not_found
    assert_match(%r{application/json}, response.content_type)
  end

  test "el idioma sigue Accept-Language" do
    get "/api/v1/nada", headers: { "Accept-Language" => "en" }
    assert_equal "Route not found", response.parsed_body.dig("error", "message")
  end

  test "las rutas que sí existen no cambian" do
    get "/up"
    assert_response :success
    get "/api/v1/plans"
    assert_response :success
  end
end
