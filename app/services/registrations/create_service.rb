# Registro público (US3, contracts/api.md "POST /registrations"): crea en una transacción la empresa,
# su dueño activo, el vínculo UserCompany (rol owner en esa empresa) y la prueba gratuita del plan elegido.
module Registrations
  class CreateService
    Result = Data.define(:user, :company, :subscription)

    USER_FIELDS = %i[first_name last_name phone email password].freeze

    def initialize(params)
      @params = params.to_h.symbolize_keys
    end

    def call
      plan = valid_plan!
      cycle = valid_billing_cycle!
      user = User.new(@params.slice(*USER_FIELDS).merge(active: true))
      company = Company.new(name: @params[:company_name], slug: available_slug)
      validate!(user, company)

      ActiveRecord::Base.transaction do
        company.save!
        user.save!
        UserCompany.create!(user: user, company: company, role: :owner)
        # Company crea la prueba Pro en su after_create; aquí queda en el plan elegido.
        company.subscription.update!(plan: plan, billing_cycle: cycle)
      end

      Result.new(user: user, company: company, subscription: company.subscription)
    end

    private

    def valid_plan!
      Plan.find(@params[:plan].to_s).key
    rescue KeyError
      raise ApiErrors::BadRequestError.new(details: I18n.t("errors.subscription.invalid_plan"))
    end

    def valid_billing_cycle!
      cycle = @params[:billing_cycle].presence || "monthly"
      return cycle.to_sym if Plan::CYCLES.include?(cycle.to_s.to_sym)

      raise ApiErrors::BadRequestError.new(details: I18n.t("errors.subscription.invalid_billing_cycle"))
    end

    # Si el slug ya existe se le agrega un sufijo numérico: cafe-ana, cafe-ana-2, cafe-ana-3...
    def available_slug
      base = @params[:company_name].to_s.parameterize
      return nil if base.blank?

      slug = base
      suffix = 1
      slug = "#{base}-#{suffix += 1}" while Company.exists?(slug: slug)
      slug
    end

    def validate!(user, company)
      user_valid = user.valid?
      company_valid = company.valid?
      return if user_valid && company_valid

      raise ApiErrors::UnprocessableEntityError.new(
        message: I18n.t("errors.validation_failed"),
        details: company.errors.full_messages + user.errors.full_messages
      )
    end
  end
end
