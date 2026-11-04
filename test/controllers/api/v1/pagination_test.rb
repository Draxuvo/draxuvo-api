require "test_helper"

# Spec 054 (H-46): una página o un tamaño de página inválidos son un dato inválido (422), no un 500, en todos los
# listados paginados; una página más allá de la última devuelve la última.
class Api::V1::PaginationTest < ActionDispatch::IntegrationTest
  LISTS = %w[tickets work_orders products employees attendances payroll_runs stock_counts product_imports company/members].freeze

  setup do
    @owner = users(:pro_co_owner)
    @company = companies(:pro_co)
  end

  def list(path, query)
    get "/api/v1/#{path}?#{query}", headers: auth_headers(@owner, @company)
  end

  LISTS.each do |path|
    test "#{path} answers 422 for an invalid page or page size" do
      %w[page=0 page=-1 page=abc page=%20 page_size=0 page_size=-3 page_size=abc].each do |query|
        list(path, query)
        assert_response :unprocessable_entity, "#{path}?#{query} → #{response.status} #{response.body.first(120)}"
        details = response.parsed_body.dig("error", "details")
        assert_equal "invalid_pagination", details["code"]
        assert_equal query.start_with?("page_size") ? "page_size" : "page", details["param"]
      end
    end

    test "#{path} answers the last page for a page beyond the end" do
      list(path, "page=9999")
      assert_response :ok, "#{path}?page=9999 → #{response.status}"
      info = response.parsed_body["info"]
      assert_equal info["pages_total"], info["page_index"]
    end

    test "#{path} keeps limiting an oversized page size and accepting decimals" do
      list(path, "page_size=100000")
      assert_response :ok
      assert_equal 100, response.parsed_body.dig("info", "page_size")
      list(path, "page=1.5")
      assert_response :ok
    end
  end

  test "a valid page and page size still paginate" do
    list("work_orders", "page=1&page_size=2")
    assert_response :ok
    assert_equal 2, response.parsed_body.dig("info", "page_size")
    assert_operator response.parsed_body["results"].size, :<=, 2
  end
end
