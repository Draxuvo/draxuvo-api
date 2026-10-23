module Payroll
  # Error de negocio de la nómina: `code` es la clave de payroll.errors.* y `status` el HTTP con el que responde.
  class Error < StandardError
    attr_reader :code, :status, :details

    def initialize(code, status: :unprocessable_entity, details: {})
      @code = code
      @status = status
      @details = details.merge(code: code.to_s)
      super(code.to_s)
    end
  end
end
