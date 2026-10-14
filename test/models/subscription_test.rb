require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  # --- enum plan ----------------------------------------------------------

  test "el enum plan usa las claves basic, pro y enterprise con los enteros 0, 1 y 2" do
    assert_equal({ "basic" => 0, "pro" => 1, "enterprise" => 2 }, Subscription.plans)
  end

  test "las suscripciones de los fixtures exponen el plan con las claves nuevas" do
    assert_equal "basic", subscriptions(:basic_co).plan
    assert_equal "pro", subscriptions(:pro_co).plan
    assert_equal "enterprise", subscriptions(:enterprise_co).plan
  end

  # --- start_trial! -------------------------------------------------------

  test "start_trial! crea una prueba con el plan elegido" do
    company = companies(:one)
    subscriptions(:one).destroy!

    freeze_time do
      subscription = Subscription.start_trial!(company, plan: :basic)

      assert subscription.persisted?
      assert_equal company, subscription.company
      assert_equal "basic", subscription.plan
      assert_equal "trialing", subscription.status
      assert_equal "monthly", subscription.billing_cycle
      assert_equal 0, subscription.amount_cents
      assert_equal 30.days.from_now, subscription.trial_ends_at
      assert_equal false, subscription.cancel_at_period_end
    end
  end

  test "start_trial! acepta pro y enterprise" do
    subscriptions(:one).destroy!
    subscriptions(:two).destroy!

    assert_equal "pro", Subscription.start_trial!(companies(:one), plan: :pro).plan
    assert_equal "enterprise", Subscription.start_trial!(companies(:two), plan: :enterprise).plan
  end

  test "start_trial! exige el plan" do
    subscriptions(:one).destroy!

    assert_raises(ArgumentError) { Subscription.start_trial!(companies(:one)) }
  end

  test "start_trial! no crea una segunda suscripción para la misma empresa" do
    assert_no_difference -> { Subscription.count } do
      assert_raises(ActiveRecord::RecordInvalid) do
        Subscription.start_trial!(companies(:pro_co), plan: :pro)
      end
    end
  end

  # --- active_access? -----------------------------------------------------

  test "active_access? es verdadero en trialing con trial_ends_at futuro" do
    assert subscriptions(:one).active_access?
  end

  test "active_access? es falso en trialing con trial_ends_at vencido" do
    subscription = subscriptions(:one)
    subscription.trial_ends_at = 1.minute.ago

    assert_not subscription.active_access?
  end

  test "active_access? es falso en trialing sin trial_ends_at" do
    subscription = subscriptions(:one)
    subscription.trial_ends_at = nil

    assert_not subscription.active_access?
  end

  test "active_access? es verdadero en active y en past_due" do
    assert subscriptions(:pro_co).active_access?
    assert subscriptions(:past_due_co).active_access?
  end

  test "active_access? sigue verdadero en active con cancelación programada" do
    subscription = subscriptions(:pro_co)
    subscription.cancel_at_period_end = true

    assert subscription.active_access?
  end

  test "active_access? es falso en expired y en cancelled" do
    assert_not subscriptions(:expired_co).active_access?

    cancelled = subscriptions(:basic_co)
    cancelled.status = :cancelled
    assert_not cancelled.active_access?
  end

  # --- montos con IVA -----------------------------------------------------

  test "IVA_RATE es 16%" do
    assert_equal 0.16, Subscription::IVA_RATE
  end

  test "iva_cents y total_cents en centavos enteros para el plan pro mensual" do
    subscription = subscriptions(:pro_co)

    assert_equal 70_000, subscription.amount_cents
    assert_equal 11_200, subscription.iva_cents
    assert_equal 81_200, subscription.total_cents
  end

  test "iva_cents y total_cents para basic mensual y enterprise anual" do
    basic = subscriptions(:basic_co)
    assert_equal 6_384, basic.iva_cents
    assert_equal 46_284, basic.total_cents

    enterprise = subscriptions(:enterprise_co)
    assert_equal 207_840, enterprise.iva_cents
    assert_equal 1_506_840, enterprise.total_cents
  end

  test "iva_cents y total_cents son enteros y valen cero en la prueba" do
    trial = subscriptions(:one)

    assert_kind_of Integer, subscriptions(:pro_co).iva_cents
    assert_kind_of Integer, subscriptions(:pro_co).total_cents
    assert_equal 0, trial.iva_cents
    assert_equal 0, trial.total_cents
  end

  test "amount, iva_amount y total_with_iva se conservan en pesos" do
    subscription = subscriptions(:pro_co)

    assert_equal 700.0, subscription.amount
    assert_equal 112.0, subscription.iva_amount
    assert_equal 812.0, subscription.total_with_iva
  end

  test "amount_cents no puede ser negativo" do
    subscription = subscriptions(:pro_co)
    subscription.amount_cents = -1

    assert_not subscription.valid?
    assert subscription.errors.of_kind?(:amount_cents, :greater_than_or_equal_to)
  end

  # --- unicidad por empresa -----------------------------------------------

  test "una empresa no puede tener dos suscripciones (validación)" do
    duplicate = Subscription.new(
      company: companies(:pro_co),
      plan: :basic,
      status: :trialing,
      billing_cycle: :monthly,
      amount_cents: 0,
      trial_ends_at: 30.days.from_now
    )

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:company_id, :taken)
  end

  test "una empresa no puede tener dos suscripciones (índice único en la BD)" do
    duplicate = Subscription.new(
      company: companies(:pro_co),
      plan: :basic,
      status: :trialing,
      billing_cycle: :monthly,
      amount_cents: 0,
      trial_ends_at: 30.days.from_now
    )

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end
end
