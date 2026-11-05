module Push
  # Stock bajo por push (spec 057, US5, FR-014): sale junto con el aviso inmediato agrupado (`StockAlerts::Dispatch`),
  # nunca con el resumen diario, a dueño y administradores con «Stock bajo» encendido (independiente del correo). Lleva
  # cuántos productos y hasta tres nombres. Un fallo de Expo se registra como fallido y no se reintenta: el resumen
  # diario por correo y la campana siguen cubriendo lo que está bajo.
  class LowStock
    KIND = "low_stock".freeze
    NAMES = 3

    def self.call(**args) = new(**args).call

    def initialize(company:, products:, now: Time.current)
      @company = company
      @products = products.to_a
      @now = now
    end

    def call
      return if @products.empty? || !Eligibility.company_ok?(@company, KIND)

      @company.user_companies.where(role: %i[owner admin]).includes(:user).each do |membership|
        Deliver.call(company: @company, user: membership.user, message: message, subject_key: subject_key)
      rescue ExpoClient::Transient => e
        Deliver.record(company: @company, user: membership.user, kind: KIND, subject_key: subject_key, status: "failed", error: e.message)
      end
    end

    private

    def subject_key = "low_stock:#{@now.to_i}"

    def message
      names = @products.first(NAMES).map { |product| Message.truncate(product.name, 30) }.join(", ")
      names += "…" if @products.size > NAMES
      @message ||= Message.new(kind: KIND, company: @company, path: "/alertas", subject_id: nil, body_key: KIND,
                               body_args: { count: @products.size, names: names })
    end
  end
end
