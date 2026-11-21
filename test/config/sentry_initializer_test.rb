require "test_helper"

# Spec 071: sin SENTRY_DSN (pruebas, CI, desarrollo) Sentry no se inicializa y reportar no hace nada ni falla.
class SentryInitializerTest < ActiveSupport::TestCase
  test "Sentry is not initialized without a DSN" do
    assert_nil ENV["SENTRY_DSN"].presence
    assert_not Sentry.initialized?
  end

  test "capturing an exception without a DSN is a no-op" do
    assert_nothing_raised { Sentry.capture_exception(RuntimeError.new("prueba")) }
    assert_nothing_raised { Sentry.set_user(id: 1) }
    assert_nothing_raised { Sentry.set_tags(company_id: 1, demo: false) }
  end
end
