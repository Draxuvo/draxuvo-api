module PaymentTerminals
  # Liga un dispositivo del proveedor como terminal integrada de la empresa (spec 069, FR-006 a FR-009): comprueba que el
  # dispositivo esté en la cuenta, que no esté ligado en ninguna empresa, lo deja en modo de cobro desde un sistema y crea
  # la terminal con el proveedor de la conexión.
  class Link
    Result = Struct.new(:terminal, :restart_required, keyword_init: true)

    def self.call(company:, user:, connection_id:, device_id:, name:) = new(company, user, connection_id, device_id, name).call

    def initialize(company, user, connection_id, device_id, name)
      @company = company
      @user = user
      @connection = company.terminal_connections.find(connection_id)
      @device_id = device_id.to_s.strip
      @name = name
    end

    def call
      TerminalConnections::Errors.ensure_connected!(@connection)
      conflict!(:device_already_linked) if PaymentTerminal.exists?(provider: @connection.provider, device_id: @device_id)

      preparation = prepare!
      terminal = @company.payment_terminals.create!(name: @name, provider: @connection.provider, terminal_connection: @connection,
                                                    device_id: @device_id, device_mode: preparation.mode)
      TerminalEvent.log!(:device_linked, terminal: terminal, connection: @connection, user: @user, device_id: @device_id)
      if preparation.restart_required
        TerminalEvent.log!(:device_prepared, terminal: terminal, connection: @connection, user: @user, mode: preparation.mode)
      end
      Result.new(terminal: terminal, restart_required: preparation.restart_required)
    rescue ActiveRecord::RecordNotUnique
      conflict!(:device_already_linked)
    end

    # Vuelve a dejar en modo de cobro desde un sistema una terminal ya ligada (por si el negocio lo cambió).
    def self.prepare!(terminal, user:)
      raise_invalid!(:not_integrated) unless terminal.integrated?
      connection = terminal.terminal_connection
      TerminalConnections::Errors.ensure_connected!(connection)
      preparation = translate do
        TerminalConnections::Errors.wrap(connection) { TerminalProviders.for(connection.provider).prepare_device(connection, terminal.device_id) }
      end
      terminal.update!(device_mode: preparation.mode)
      TerminalEvent.log!(:device_prepared, terminal: terminal, connection: connection, user: user, mode: preparation.mode)
      preparation
    end

    def self.translate
      yield
    rescue TerminalProviders::Error => e
      raise_invalid!(e.failure.reason == "device_not_found" ? :device_not_found : :device_not_supported)
    end

    def self.raise_invalid!(code)
      raise ApiErrors::UnprocessableEntityError.new(message: I18n.t("payment_terminal.errors.#{code}"), details: { code: code.to_s })
    end

    private

    def prepare!
      self.class.translate do
        TerminalConnections::Errors.wrap(@connection) do
          TerminalProviders.for(@connection.provider).prepare_device(@connection, @device_id)
        end
      end
    end

    def conflict!(code)
      raise ApiErrors::BaseError.new(status: :conflict, message: I18n.t("payment_terminal.errors.#{code}"), details: { code: code.to_s })
    end
  end
end
