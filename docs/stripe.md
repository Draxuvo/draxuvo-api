# Stripe: configuración del cobro

La API cobra con Stripe Checkout. El estado de cada suscripción llega por webhook. El dueño de la empresa administra su suscripción en el Customer Portal de Stripe.

## Productos y precios

Crea tres productos en MXN: Básico, Pro y Empresa. Cada uno lleva un Price mensual y uno anual, recurrentes y sin IVA. La API busca cada Price por su `lookup_key`, así que no hay IDs en variables de entorno:

| Plan | Mensual | `lookup_key` mensual | Anual | `lookup_key` anual |
|---|---|---|---|---|
| Básico | 399.00 | `draxuvo_basic_monthly` | 3,990.00 | `draxuvo_basic_annual` |
| Pro | 700.00 | `draxuvo_pro_monthly` | 7,000.00 | `draxuvo_pro_annual` |
| Empresa | 1,299.00 | `draxuvo_enterprise_monthly` | 12,990.00 | `draxuvo_enterprise_annual` |

Los montos tienen que coincidir con `app/models/plan.rb`, porque la UI los muestra desde ahí. Para cambiar un precio, crea un Price nuevo, pásale el `lookup_key` (opción *transfer lookup key*) y actualiza `Plan`. El ID resuelto se guarda en cache una hora.

## Customer Portal

En *Settings → Billing → Customer portal*, activa:

- Actualizar el método de pago.
- Ver el historial de facturas.
- Cancelar la suscripción **al final del periodo**, no de inmediato.
- Cambiar de plan, con los seis precios de arriba y el prorrateo de Stripe.

La API abre el portal con `POST /api/v1/subscription/portal`.

## Webhook

Crea un endpoint hacia `https://<api>/api/v1/stripe/webhooks` con estos eventos:

- `checkout.session.completed`
- `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`
- `invoice.paid`, `invoice.payment_failed`

Para los reintentos de cobro (el periodo de gracia), activa *Smart Retries*. Al agotarlos, cancela la suscripción.

## Variables de entorno

| Variable | Uso |
|---|---|
| `STRIPE_API_KEY` | Llave secreta (`sk_live_…` o `sk_test_…`) |
| `STRIPE_WEBHOOK_SECRET` | Secreto del endpoint (`whsec_…`). Sin él, todo webhook se rechaza con 400 |

## Desarrollo local

```bash
stripe listen --forward-to localhost:3000/api/v1/stripe/webhooks   # imprime el whsec_ para .env
stripe trigger invoice.payment_failed
```

El recorrido completo de prueba está en `specs/002-rebrand-suscripciones/quickstart.md` del workspace.
