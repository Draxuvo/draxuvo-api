Stripe.api_key = ENV.fetch("STRIPE_API_KEY", nil)
# Versión que trae la gema stripe 13.5.1; fija el formato de las respuestas y los webhooks (R11).
Stripe.api_version = "2025-02-24.acacia"
