module TerminalProviders
  class MercadoPago
    # Estado de una orden de Point (API de Orders) → estado de Draxuvo (spec 069, research R1).
    #
    #   created, at_terminal  → pending
    #   processed             → approved  (refunded/partially_refunded → refunded)
    #   failed                → declined  (con el detalle del pago: rejected_by_issuer, insufficient_amount, …)
    #   action_required       → declined  con check_on_terminal (verificar en sandbox: research R1)
    #   canceled              → canceled  (canceled_on_terminal o canceled_by_api)
    #   expired               → expired
    #   refunded              → refunded
    module StatusMap
      ORDER = {
        "created" => "pending", "at_terminal" => "pending", "processed" => "approved", "failed" => "declined",
        "action_required" => "declined", "canceled" => "canceled", "expired" => "expired", "refunded" => "refunded"
      }.freeze

      # Detalles que Draxuvo sabe explicar (config/locales: terminal_charge.details.*); cualquier otro se muestra genérico.
      KNOWN_DETAILS = %w[at_terminal created cancellation_requested rejected_by_issuer insufficient_amount high_risk
                         bad_filled_card_data card_disabled amount_limit_exceeded max_attempts_exceeded
                         required_call_for_authorize processing_error invalid_installments in_review canceled_on_terminal
                         canceled_by_api expired check_on_terminal waiting_payment provider_unavailable amount_out_of_range
                         device_offline failed].freeze

      module_function

      def status(order)
        raw = order["status"].to_s
        mapped = ORDER.fetch(raw, "pending")
        detail = order["status_detail"].to_s
        mapped = "refunded" if mapped == "approved" && %w[refunded partially_refunded].include?(detail)
        mapped
      end

      def detail(order, payment)
        raw = order["status"].to_s
        candidate = payment&.dig("status_detail").presence || order["status_detail"].presence || raw
        candidate = "check_on_terminal" if raw == "action_required"
        candidate = candidate.to_s
        KNOWN_DETAILS.include?(candidate) ? candidate : candidate.first(60)
      end

      def refund_status(order)
        refunds = Array(order.dig("transactions", "refunds"))
        return nil if refunds.empty?

        refunds.all? { |r| %w[processed approved refunded].include?(r["status"].to_s) } ? "done" : "requested"
      end
    end
  end
end
