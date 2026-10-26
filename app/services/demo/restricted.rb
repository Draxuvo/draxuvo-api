# Una acción con efecto externo (cobro, cambio de plan) que una demo no puede hacer (spec 039, FR-007).
module Demo
  class Restricted < StandardError
    attr_reader :action

    # action: :payment, :plan_change, :email o :whatsapp
    def initialize(action)
      @action = action.to_sym
      super("#{I18n.t('demo.errors.demo_restricted')} (#{@action})")
    end
  end
end
