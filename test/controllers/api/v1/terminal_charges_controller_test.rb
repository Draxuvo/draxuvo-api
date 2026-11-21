require "test_helper"

# Spec 069, contracts/api.md (Solicitudes de cobro y Webhook).
class Api::V1::TerminalChargesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @company = companies(:pro_co)
    @owner = users(:pro_co_owner)
    @headers = auth_headers(@owner, @company)
    @terminal = integrated_terminal(@company)
    @order = work_orders(:pro_done)
  end

  test "crear, consultar y cancelar una solicitud" do
    with_fake_provider do
      post "/api/v1/terminal_charges", params: { terminal_id: @terminal.id, amount: "850", work_order_id: @order.id }, headers: @headers, as: :json
      assert_response :created
      body = response.parsed_body
      assert_equal "pending", body["status"]
      assert_equal "850.00", body["amount"]
      assert_equal({ "type" => "work_order", "id" => @order.id, "label" => @order.title }, body["owner"])
      assert_equal %w[cancel abandon], body["allowed_actions"]

      assert_enqueued_with(job: TerminalCharges::SyncJob) do
        TerminalCharge.find(body["id"]).update_columns(last_synced_at: 1.minute.ago)
        get "/api/v1/terminal_charges/#{body['id']}", headers: @headers
      end
      assert_response :ok

      post "/api/v1/terminal_charges/#{body['id']}/cancel", headers: @headers, as: :json
      assert_response :ok
      assert_equal "canceled", response.parsed_body["status"]
    end
  end

  test "otro miembro del personal no ve una solicitud ajena" do
    with_fake_provider do
      post "/api/v1/terminal_charges", params: { terminal_id: @terminal.id, amount: "850", work_order_id: @order.id }, headers: @headers, as: :json
      id = response.parsed_body["id"]
      get "/api/v1/terminal_charges/#{id}", headers: auth_headers(users(:pro_staff), @company)
      assert_response :forbidden
    end
  end

  test "con una solicitud abierta la orden no cambia de estado" do
    with_fake_provider do
      post "/api/v1/terminal_charges", params: { terminal_id: @terminal.id, amount: "850", work_order_id: @order.id }, headers: @headers, as: :json
      post "/api/v1/work_orders/#{@order.id}/reopen", headers: @headers, as: :json
      assert_response :unprocessable_entity
      assert_equal "terminal_charge_pending", response.parsed_body.dig("error", "details", "code")
    end
  end

  test "aplicada, la respuesta trae el resultado del cobro" do
    with_fake_provider do |fake|
      post "/api/v1/terminal_charges", params: { terminal_id: @terminal.id, amount: "850", work_order_id: @order.id }, headers: @headers, as: :json
      id = response.parsed_body["id"]
      fake.charge_status = "approved"
      perform_enqueued_jobs { TerminalCharges::SyncJob.perform_later(id) }
      get "/api/v1/terminal_charges/#{id}", headers: @headers
      body = response.parsed_body
      assert_equal "applied", body["status"]
      assert_equal @order.id, body.dig("result", "work_order_id")
    end
  end

  test "sin el módulo responde module_not_in_plan" do
    post "/api/v1/terminal_charges", params: { terminal_id: 1, amount: "1", work_order_id: 1 },
                                     headers: auth_headers(users(:basic_co_owner), companies(:basic_co)), as: :json
    assert_response :forbidden
    assert_equal "module_not_in_plan", response.parsed_body.dig("error", "details", "code")
  end

  test "webhook: firma mala 400; aviso de orden encola la consulta; id desconocido 200" do
    with_fake_provider do |fake|
      post "/api/v1/terminal_charges", params: { terminal_id: @terminal.id, amount: "850", work_order_id: @order.id }, headers: @headers, as: :json
      charge = TerminalCharge.find(response.parsed_body["id"])

      post "/api/v1/webhooks/mercado_pago?data.id=#{charge.provider_order_id}&type=order", params: { type: "order" }.to_json,
                                                                                        headers: { "x-signature" => "bad", "CONTENT_TYPE" => "application/json" }
      assert_response :bad_request

      fake.notice = TerminalProviders::Notice.new(kind: :charge, external_id: charge.provider_order_id)
      assert_enqueued_with(job: TerminalCharges::SyncJob, args: [ charge.id ]) do
        post "/api/v1/webhooks/mercado_pago?data.id=#{charge.provider_order_id}", params: { type: "order" }.to_json,
                                                                                headers: { "CONTENT_TYPE" => "application/json" }
      end
      assert_response :ok

      fake.notice = TerminalProviders::Notice.new(kind: :charge, external_id: "ORDXX")
      post "/api/v1/webhooks/mercado_pago?data.id=ORDXX", params: {}.to_json, headers: { "CONTENT_TYPE" => "application/json" }
      assert_response :ok
      assert TerminalEvent.exists?(kind: "webhook_ignored")
    end
  end

  test "webhook real: valida la firma de Mercado Pago" do
    with_env(MERCADO_PAGO_WEBHOOK_SECRET: "s3cret") do
      headers = mp_webhook_headers(data_id: "ORD123", secret: "s3cret").merge("CONTENT_TYPE" => "application/json")
      post "/api/v1/webhooks/mercado_pago?data.id=ORD123&type=order", params: { type: "order", action: "order.processed" }.to_json, headers: headers
      assert_response :ok
      bad = mp_webhook_headers(data_id: "ORD123", secret: "otro").merge("CONTENT_TYPE" => "application/json")
      post "/api/v1/webhooks/mercado_pago?data.id=ORD123&type=order", params: { type: "order" }.to_json, headers: bad
      assert_response :bad_request
    end
  end

  test "webhook mp-connect desconecta todas las empresas con esa cuenta" do
    a = terminal_connection_for(@company)
    b = terminal_connection_for(companies(:enterprise_co))
    with_fake_provider do |fake|
      fake.notice = TerminalProviders::Notice.new(kind: :disconnect, account_id: "1001")
      Resend::Emails.stub(:send, ->(*) { resend_response }) do
        post "/api/v1/webhooks/mercado_pago", params: { type: "mp-connect" }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
      end
    end
    assert_response :ok
    assert a.reload.disconnected?
    assert b.reload.disconnected?
  end

  test "el barrido marca las que nunca llegaron al proveedor y consulta las atrasadas" do
    stuck = TerminalCharge.create!(company: @company, payment_terminal: @terminal, terminal_connection: @terminal.terminal_connection,
                                   created_by: @owner, amount: 10, work_order: @order, created_at: 5.minutes.ago)
    other = integrated_terminal(@company)
    due = TerminalCharge.create!(company: @company, payment_terminal: other, terminal_connection: other.terminal_connection,
                                 created_by: @owner, amount: 10, work_order: work_orders(:pro_open), provider_order_id: "ORD9",
                                 last_synced_at: 1.minute.ago)
    assert_enqueued_with(job: TerminalCharges::SyncJob, args: [ due.id ]) { TerminalCharges::SweepJob.perform_now }
    assert_equal "declined", stuck.reload.status
  end

  # US6: pago aprobado tarde cuando la orden ya se cobró por otra vía.
  def unapplied_charge(fake)
    charge = TerminalCharges::Create.call(company: @company, user: @owner,
                                          params: { terminal_id: @terminal.id, amount: "850", work_order_id: @order.id })
    TerminalCharges::Abandon.call(charge, user: @owner)
    WorkOrders::Transition.call(@order.reload, :charge, WorkOrders::Transition::Context.new(user: @owner, role: "owner"),
                                { payments: [ { method: "cash", amount_received: "850" } ] })
    fake.charge_status = "approved"
    TerminalCharges::Sync.call(charge.reload)
    charge.reload.tap { |late| assert late.unapplied? }
  end

  test "pagos sin aplicar: lista, reembolso con confirmación y sin repetir" do
    with_fake_provider do |fake|
      charge = unapplied_charge(fake)
      get "/api/v1/terminal_charges", headers: @headers
      assert_response :ok
      row = response.parsed_body["results"].sole
      assert_equal %w[refund dismiss], row["allowed_actions"]

      post "/api/v1/terminal_charges/#{charge.id}/refund", headers: @headers, as: :json
      assert_response :unprocessable_entity
      assert_equal "refund_confirmation_required", response.parsed_body.dig("error", "details", "code")

      post "/api/v1/terminal_charges/#{charge.id}/refund", params: { confirm: true }, headers: @headers, as: :json
      assert_response :ok
      assert_equal "refunded", response.parsed_body["status"]
      assert_equal "done", response.parsed_body.dig("refund", "status")

      post "/api/v1/terminal_charges/#{charge.id}/refund", params: { confirm: true }, headers: @headers, as: :json
      assert_response :conflict
      assert_equal "already_refunded", response.parsed_body.dig("error", "details", "code")
      get "/api/v1/terminal_charges", headers: @headers
      assert_empty response.parsed_body["results"]
      assert_equal 1, fake.calls_of(:refund).size
    end
  end

  test "pagos sin aplicar: el rechazo del proveedor responde el motivo; marcar atendido lo quita de la lista" do
    with_fake_provider do |fake|
      charge = unapplied_charge(fake)
      fake.refund_error = provider_error(:declined, "insufficient_money_for_refund", http_status: 400)
      post "/api/v1/terminal_charges/#{charge.id}/refund", params: { confirm: true }, headers: @headers, as: :json
      assert_response :unprocessable_entity
      assert_equal "insufficient_money_for_refund", response.parsed_body.dig("error", "details", "reason")

      post "/api/v1/terminal_charges/#{charge.id}/dismiss", headers: @headers, as: :json
      assert_response :ok
      assert_equal "skipped", response.parsed_body.dig("refund", "status")
      assert_empty response.parsed_body["allowed_actions"]
      get "/api/v1/terminal_charges", headers: @headers
      assert_empty response.parsed_body["results"]
      get "/api/v1/terminal_charges", params: { status: "all" }, headers: @headers
      assert_equal [ charge.id ], response.parsed_body["results"].map { |r| r["id"] }
    end
  end

  test "pagos sin aplicar: el personal no reembolsa ni marca atendido" do
    with_fake_provider do |fake|
      charge = unapplied_charge(fake)
      staff = auth_headers(users(:pro_staff), @company)
      post "/api/v1/terminal_charges/#{charge.id}/refund", params: { confirm: true }, headers: staff, as: :json
      assert_response :forbidden
      post "/api/v1/terminal_charges/#{charge.id}/dismiss", headers: staff, as: :json
      assert_response :forbidden
      assert_empty fake.calls_of(:refund)
    end
  end

  test "anular el cobro integrado de una orden pide confirmar el reembolso" do
    with_fake_provider do |fake|
      charge = TerminalCharges::Create.call(company: @company, user: @owner,
                                            params: { terminal_id: @terminal.id, amount: "850", work_order_id: @order.id })
      fake.charge_status = "approved"
      TerminalCharges::Sync.call(charge.reload)

      post "/api/v1/work_orders/#{@order.id}/void_charge", params: { reason: "Error" }, headers: @headers, as: :json
      assert_response :unprocessable_entity
      refunds = response.parsed_body.dig("error", "details", "refunds")
      assert_equal [ { "ticket_payment_id" => charge.reload.ticket_payment_id, "amount" => "850.00",
                       "terminal" => { "id" => @terminal.id, "name" => @terminal.name, "provider" => "mercado_pago" } } ],
                   refunds.map { |r| r.slice("ticket_payment_id", "amount", "terminal").merge("terminal" => r["terminal"].slice("id", "name", "provider")) }

      post "/api/v1/work_orders/#{@order.id}/void_charge", params: { reason: "Error", refund: "confirm" }, headers: @headers, as: :json
      assert_response :ok
      assert_equal "done", @order.reload.status
      assert charge.reload.terminal_refund.done?
    end
  end
end
