# Cancela un artículo ya mandado, con motivo (FR-030, FR-031). Lo nuevo lo cancela el mesero de la cuenta o un
# encargado; lo que ya está en preparación o listo, solo un encargado o superior. Un cancelado deja de contar en el total.
module Restaurant
  class CancelItem
    def self.call(item, context, reason) = new(item, context, reason).call

    def initialize(item, context, reason)
      @item = item
      @context = context
      @reason = reason.to_s.strip
    end

    def call
      CheckItem.transaction do
        @item.lock!
        check = @item.check
        fail!(:check_not_open) unless check.status_open?
        fail!(:invalid_transition) if @item.status_draft? || @item.status_delivered? || @item.status_cancelled?
        raise ApiErrors::ForbiddenError.new(message: I18n.t("auth.not_authorized")) unless Permissions.cancel_item?(@item, @context)

        fail!(:reason_required) if @reason.empty?

        @item.update!(status: :cancelled, cancelled_at: Time.current, cancel_reason: @reason, cancelled_by: @context.user)
        @item
      end
    end

    private

    def fail!(code)
      raise ApiErrors::UnprocessableEntityError.new(
        message: I18n.t("restaurant.errors.#{code}"), details: { code: code.to_s }
      )
    end
  end
end
