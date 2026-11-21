module TerminalConnections
  # Dispositivos de la cuenta en el proveedor, paginados por el proveedor (spec 069, contracts/api.md, Complexity
  # Tracking del plan). Marca cuáles ya están ligados en esta empresa y cuáles en otra.
  class Devices
    MAX_PAGE_SIZE = 50

    Result = Struct.new(:devices, :total, :page, :page_size, keyword_init: true)

    def self.call(connection, page:, page_size:, search: nil) = new(connection, page, page_size, search).call

    def initialize(connection, page, page_size, search)
      @connection = connection
      @page = [ page.to_i, 1 ].max
      @page_size = page_size.to_i.clamp(1, MAX_PAGE_SIZE)
      @page_size = 20 if page_size.blank?
      @search = search.to_s.strip.downcase
    end

    def call
      Errors.ensure_connected!(@connection)
      list, total = Errors.wrap(@connection) do
        TerminalProviders.for(@connection.provider).devices(@connection, limit: @page_size, offset: (@page - 1) * @page_size)
      end
      list = list.select { |device| device.id.to_s.downcase.include?(@search) || device.label.to_s.downcase.include?(@search) } if @search.present?
      linked = PaymentTerminal.where(provider: @connection.provider, device_id: list.map(&:id)).index_by(&:device_id)
      rows = list.map do |device|
        terminal = linked[device.id]
        mine = terminal && terminal.company_id == @connection.company_id
        { device_id: device.id, label: device.label, mode: device.mode, store_id: device.store_id, pos_id: device.pos_id,
          linked_terminal: (mine ? { id: terminal.id, name: terminal.name } : nil),
          linkable: terminal.nil?, reason: (terminal && !mine ? "linked_elsewhere" : nil) }
      end
      Result.new(devices: rows, total: total.to_i, page: @page, page_size: @page_size)
    end
  end
end
