require "test_helper"

class Api::V1::SalesTicketTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:pos_co)
    @staff = users(:pos_staff)
    @admin = users(:pos_admin)
    @sale = open_sale(@staff, [ products(:pos_cuaderno), 2 ])
    charge_cash(@sale, @staff, received: 100)
    @sale.reload
  end

  def headers(user = @staff) = auth_headers(user, @company)

  def json = response.parsed_body

  test "GET ticket returns the folio, items and payments of a paid sale" do
    get "/api/v1/sales/#{@sale.id}/ticket", headers: headers
    assert_response :ok
    assert_equal @sale.ticket.folio, json["folio"]
    assert_equal "paid", json["status"]
    assert_equal "Papelería Prueba", json.dig("company", "name")
    assert_equal "Cuaderno profesional", json["items"].first["description"]
    assert_equal 1, json["payments"].size
    assert_equal @sale.id, json.dig("sale", "id")
  end

  test "an open sale has no ticket yet" do
    open = open_sale(@staff, [ products(:pos_pluma), 1 ])
    get "/api/v1/sales/#{open.id}/ticket", headers: headers
    assert_response :unprocessable_entity
    assert_equal "sale_not_paid", json.dig("error", "details", "code")
    get "/api/v1/sales/#{open.id}/ticket.pdf", headers: headers
    assert_response :unprocessable_entity
  end

  test "PDF defaults to a4 and can be asked in thermal widths" do
    get "/api/v1/sales/#{@sale.id}/ticket.pdf", headers: headers
    assert_response :ok
    assert_equal "application/pdf", response.media_type
    assert response.body.start_with?("%PDF")
    assert_match(/ticket-T-\d+-a4\.pdf/, response.headers["Content-Disposition"])
    a4 = response.body.b.match(/MediaBox \[0(?:\.0)? 0(?:\.0)? ([\d.]+)/)[1].to_f

    get "/api/v1/sales/#{@sale.id}/ticket.pdf", params: { paper: "thermal58" }, headers: headers
    assert_response :ok
    assert_match(/thermal58/, response.headers["Content-Disposition"])
    narrow = response.body.b.match(/MediaBox \[0(?:\.0)? 0(?:\.0)? ([\d.]+)/)[1].to_f
    assert_operator narrow, :<, a4

    get "/api/v1/sales/#{@sale.id}/ticket.pdf", params: { paper: "thermal80" }, headers: headers
    assert_response :ok
  end

  test "an unknown paper is rejected" do
    get "/api/v1/sales/#{@sale.id}/ticket.pdf", params: { paper: "poster" }, headers: headers
    assert_response :unprocessable_entity
    assert_equal "invalid_format", json.dig("error", "details", "code")
  end

  test "works without the tickets module (Básico with pos)" do
    assert_not @company.module_active?(:tickets)
    get "/api/v1/sales/#{@sale.id}/ticket", headers: headers
    assert_response :ok
  end

  test "another cashier cannot read my ticket but an admin can" do
    get "/api/v1/sales/#{@sale.id}/ticket", headers: headers(users(:pos_staff2))
    assert_response :not_found
    get "/api/v1/sales/#{@sale.id}/ticket.pdf", headers: headers(@admin)
    assert_response :ok
  end

  test "without the pos module there is no ticket access" do
    get "/api/v1/sales/#{@sale.id}/ticket", headers: auth_headers(users(:pro_co_owner), companies(:pro_co))
    assert_response :forbidden
  end

  test "WhatsApp needs the whatsapp module" do
    post "/api/v1/sales/#{@sale.id}/ticket/whatsapp", params: { phone: "5512345678" }, headers: headers, as: :json
    assert_response :forbidden
    assert_equal "module_not_in_plan", json.dig("error", "details", "code")
    assert_equal "whatsapp", json.dig("error", "details", "module")
  end

  test "WhatsApp sends the ticket PDF when the module is active" do
    @company.update_columns(parent_company_id: nil)
    @company.billing_subscription.update!(plan: :enterprise)
    grant_addon!(@company, :pos)
    sent = []
    fake = Struct.new(:calls) do
      def call = calls << :sent && { "messages" => [ { "id" => "wamid.1" } ] }
    end
    service = fake.new(sent)
    Whatsapp::TicketService.stub(:new, ->(ticket, phone:) { assert_equal @sale.ticket, ticket; assert_equal "5512345678", phone; service }) do
      post "/api/v1/sales/#{@sale.id}/ticket/whatsapp", params: { phone: "5512345678" }, headers: headers, as: :json
    end

    assert_response :ok
    assert_equal [ :sent ], sent
    assert json["message"].present?
  end

  test "WhatsApp needs a phone" do
    @company.billing_subscription.update!(plan: :enterprise)
    post "/api/v1/sales/#{@sale.id}/ticket/whatsapp", params: { phone: " " }, headers: headers, as: :json
    assert_response :bad_request
  end

  test "WhatsApp is simulated in a demo" do
    @company.billing_subscription.update!(plan: :enterprise)
    Demo::Guard.stub(:active?, true) do
      post "/api/v1/sales/#{@sale.id}/ticket/whatsapp", params: { phone: "5512345678" }, headers: headers, as: :json
    end
    assert_response :ok
    assert_equal true, json["demo"]
  end
end
