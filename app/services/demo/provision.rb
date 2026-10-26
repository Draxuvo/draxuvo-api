# Abre una demo (spec 039): crea la empresa de demostración con los datos de un escenario, su usuario dueño efímero y
# la apertura, y devuelve el JWT que caduca con la demo. Todo en una transacción: si algo falla no queda nada.
#
# Antes de crear nada toma una de las `Demo::Config.max_provisioning` ranuras de aprovisionamiento (candado de
# sesión de PostgreSQL, sin gemas) para que una ráfaga de demos no ocupe la API y la base que usan los clientes
# reales; sin ranura libre lanza Demo::Busy.
module Demo
  class Provision
    LOCK_KEY = 39_000
    EMAIL_DOMAIN = "demo.invalid".freeze
    NAMES = {
      "es" => { first: "Dueño", last: "Demo" },
      "en" => { first: "Owner", last: "Demo" }
    }.freeze

    Result = Data.define(:company, :branch, :user, :session, :token)

    def self.call(**kwargs) = new(**kwargs).call

    def self.lock_connection = ActiveRecord::Base.connection

    # Devuelve el número de la ranura tomada o nil si todas están ocupadas.
    def self.acquire_slot
      Demo::Config.max_provisioning.times do |slot|
        return slot if lock_connection.select_value("SELECT pg_try_advisory_lock(#{LOCK_KEY}, #{slot})")
      end
      nil
    end

    def self.release_slot(slot)
      lock_connection.execute("SELECT pg_advisory_unlock(#{LOCK_KEY}, #{slot})")
    end

    def initialize(plan:, scenario:, locale: "es", contact: nil, invite: nil)
      @plan = plan.to_s
      @scenario = scenario.to_s
      @locale = locale.to_s
      @contact = normalize_contact(contact)
      @invite = invite
      raise ArgumentError, "el escenario #{@scenario} no es del plan #{@plan}" unless Demo::Scenarios.valid?(@plan, @scenario)
    end

    def call
      slot = self.class.acquire_slot
      raise Busy, I18n.t("demo.errors.demo_busy") if slot.nil?

      begin
        ActiveRecord::Base.transaction { build }
      ensure
        self.class.release_slot(slot)
      end
    end

    private

    def build
      scenario = Demo::Scenarios.fetch(@scenario)
      company = create_company(scenario)
      branch = create_branch(company, scenario)
      user = create_owner(company, branch)
      scenario.call(company: company, owner: user, branch: branch)
      session = create_session(company, user)
      Result.new(company: company, branch: branch, user: user, session: session, token: token_for(user, session))
    end

    def create_company(scenario)
      company = Company.create!(name: scenario::COMPANY_NAME, slug: "demo-#{SecureRandom.hex(6)}", demo: true,
                                order_mode: scenario::ORDER_MODE)
      plan = Plan.find(@plan)
      company.subscription.update!(plan: plan.key, status: :active, billing_cycle: :monthly, amount_cents: 0,
                                   trial_ends_at: nil, current_period_start: Time.current,
                                   current_period_end: 1.year.from_now)
      company
    end

    def create_branch(company, scenario)
      return nil unless scenario.const_defined?(:BRANCH_NAME)

      Company.create!(name: scenario::BRANCH_NAME, slug: "demo-#{SecureRandom.hex(6)}", demo: true, parent: company,
                      order_mode: company.order_mode)
    end

    def create_owner(company, branch)
      names = NAMES.fetch(@locale, NAMES["es"])
      user = User.create!(first_name: names[:first], last_name: names[:last], active: true,
                          phone: "5500000000", email: "demo-#{SecureRandom.hex(8)}@#{EMAIL_DOMAIN}", password: "#{SecureRandom.base64(24)}aA1!")
      [ company, branch ].compact.each { |target| UserCompany.create!(user: user, company: target, role: :owner) }
      user
    end

    def create_session(company, user)
      DemoSession.create!(company: company, user: user, demo_invite: @invite, plan: @plan, scenario: @scenario,
                          locale: @locale, expires_at: Demo::Config.ttl.from_now,
                          contact_name: @contact[:name], contact_email: @contact[:email], contact_phone: @contact[:phone])
    end

    def token_for(user, session)
      JwtHelper.jwt_encode({ user_id: user.id, email: user.email, full_name: user.full_name, exp: session.expires_at.to_i })
    end

    def normalize_contact(contact)
      data = (contact || {}).to_h.with_indifferent_access
      { name: data[:name].to_s.strip.presence, email: data[:email].to_s.strip.downcase.presence,
        phone: data[:phone].to_s.gsub(/\D/, "").presence }
    end
  end
end
