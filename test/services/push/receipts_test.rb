require "test_helper"

class Push::ReceiptsTest < ActiveSupport::TestCase
  class ReceiptsClient
    attr_reader :asked

    def initialize(receipts = {}, raise_error: nil)
      @receipts = receipts
      @raise_error = raise_error
      @asked = []
    end

    def receipts(ids)
      raise @raise_error if @raise_error

      @asked.concat(ids)
      @receipts.slice(*ids)
    end
  end

  setup do
    @company = companies(:resto_co)
    @user = users(:resto_waiter)
    @ok = register_device(@user)
    @gone = register_device(@user)
  end

  def delivery(age:, tickets:, status: "sent")
    PushDelivery.create!(company: @company, user: @user, kind: "check_ready", subject_key: "kitchen_order:1", status: status,
                         tickets: tickets, created_at: age.ago)
  end

  test "a DeviceNotRegistered receipt disables that phone and the delivery is marked checked" do
    checked = delivery(age: 20.minutes, tickets: [ { "id" => "t1", "device_id" => @ok.id }, { "id" => "t2", "device_id" => @gone.id } ])
    client = ReceiptsClient.new({ "t1" => { "status" => "ok" }, "t2" => { "status" => "error", "details" => { "error" => "DeviceNotRegistered" } } })

    Push::Receipts.call(client: client)

    assert_nil @ok.reload.disabled_at
    assert_equal "not_registered", @gone.reload.disabled_reason
    assert_not_nil checked.reload.receipts_checked_at
  end

  test "only asks for sent deliveries between 15 minutes and 24 hours old, once" do
    delivery(age: 5.minutes, tickets: [ { "id" => "too-new", "device_id" => @ok.id } ])
    delivery(age: 2.days, tickets: [ { "id" => "too-old", "device_id" => @ok.id } ])
    delivery(age: 1.hour, tickets: [], status: "skipped_preference")
    delivery(age: 1.hour, tickets: [ { "id" => "due", "device_id" => @ok.id } ])
    client = ReceiptsClient.new

    Push::Receipts.call(client: client)
    Push::Receipts.call(client: client)

    assert_equal [ "due" ], client.asked
  end

  test "a transient failure leaves deliveries unchecked for the next run" do
    pending = delivery(age: 1.hour, tickets: [ { "id" => "t1", "device_id" => @ok.id } ])

    Push::Receipts.call(client: ReceiptsClient.new(raise_error: Push::ExpoClient::Transient.new("expo_http_503")))

    assert_nil pending.reload.receipts_checked_at
  end
end
