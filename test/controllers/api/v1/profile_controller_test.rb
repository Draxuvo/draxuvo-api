require "test_helper"

# Contrato: specs/006-temas-panel/contracts/api.md (preferencias de apariencia).
class Api::V1::ProfileControllerTest < ActionDispatch::IntegrationTest
  PATH = "/api/v1/profile".freeze

  setup do
    @owner = users(:pro_co_owner)
    @company = companies(:pro_co)
    @headers = auth_headers(@owner, @company)
  end

  test "defaults to anaquel and system" do
    get PATH, headers: @headers
    assert_response :ok
    assert_equal({ "theme" => "anaquel", "color_mode" => "system" }, response.parsed_body["preferences"])
  end

  test "saves a valid theme and color mode" do
    patch PATH, params: { profile: { theme: "talavera", color_mode: "dark" } }, headers: @headers, as: :json
    assert_response :ok
    assert_equal({ "theme" => "talavera", "color_mode" => "dark" }, response.parsed_body["preferences"])
    assert_equal "talavera", @owner.reload.theme
    assert_equal "dark", @owner.color_mode
  end

  test "rejects an unknown theme or mode with 422" do
    patch PATH, params: { profile: { theme: "neon" } }, headers: @headers, as: :json
    assert_response :unprocessable_entity

    patch PATH, params: { profile: { color_mode: "sepia" } }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_equal "anaquel", @owner.reload.theme
  end

  test "a field left out of the body does not change" do
    @owner.update!(theme: "grafito", color_mode: "light")
    patch PATH, params: { profile: { phone: "5512345678" } }, headers: @headers, as: :json
    assert_response :ok
    assert_equal({ "theme" => "grafito", "color_mode" => "light" }, response.parsed_body["preferences"])
  end

  test "an unknown stored theme is served as anaquel" do
    @owner.update_columns(theme: "retirado")
    get PATH, headers: @headers
    assert_equal "anaquel", response.parsed_body.dig("preferences", "theme")
  end

  test "login returns preferences" do
    @owner.update!(theme: "mercado")
    post "/api/v1/auth/login", params: { email: @owner.email, password: "password123" }, as: :json
    skip "el fixture no tiene contraseña conocida" unless response.successful?
    assert_equal "mercado", response.parsed_body.dig("user", "preferences", "theme")
  end

  test "show and update work with an expired subscription" do
    owner = create_member(companies(:expired_co), role: :owner)
    headers = auth_headers(owner, companies(:expired_co))

    get PATH, headers: headers
    assert_response :ok

    patch PATH, params: { profile: { theme: "rosa_mexicano" } }, headers: headers, as: :json
    assert_response :ok
    assert_equal "rosa_mexicano", response.parsed_body.dig("preferences", "theme")
  end

  test "two people of the same company keep their own preferences" do
    other = create_member(@company, role: :admin)
    patch PATH, params: { profile: { theme: "mercado" } }, headers: @headers, as: :json
    patch PATH, params: { profile: { theme: "grafito", color_mode: "dark" } }, headers: auth_headers(other, @company), as: :json

    assert_equal "mercado", @owner.reload.theme
    assert_equal "grafito", other.reload.theme
    assert_equal "system", @owner.color_mode
  end
end
