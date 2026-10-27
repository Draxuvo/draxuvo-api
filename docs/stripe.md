# Stripe: configuración del cobro

La API cobra con Stripe Checkout. El estado de cada suscripción llega por webhook. El dueño de la empresa administra su suscripción en el Customer Portal de Stripe.

## Productos y precios

Crea tres productos en MXN: Básico, Pro y Empresa. Cada uno lleva un Price mensual y uno anual, recurrentes y sin IVA. La API busca cada Price por su `lookup_key`, así que no hay IDs en variables de entorno:

| Plan | Mensual | `lookup_key` mensual | Anual | `lookup_key` anual |
|---|---|---|---|---|
| Básico | 399.00 | `draxuvo_basic_monthly` | 3,990.00 | `draxuvo_basic_annual` |
| Pro | 799.00 | `draxuvo_pro_monthly` | 7,990.00 | `draxuvo_pro_annual` |
| Empresa | 1,599.00 | `draxuvo_enterprise_monthly` | 15,990.00 | `draxuvo_enterprise_annual` |

Los montos tienen que coincidir con `app/models/plan.rb`, porque la UI los muestra desde ahí. Para cambiar un precio, crea un Price nuevo, pásale el `lookup_key` (opción *transfer lookup key*) y actualiza `Plan`. El ID resuelto se guarda en cache una hora. Al subir Pro y Empresa a 799 y 1,599 (spec 041) solo hacen falta Prices nuevos para esos dos planes, mensual y anual; el de Básico no cambia.

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

## Pasar de modo prueba a modo real

Draxuvo sale en **modo prueba** (cuenta `Draxuvo sandbox`): se valida el flujo completo sin cobrar. El paso a modo real es
un cambio de claves y de IDs; no cambia código. Hazlo solo tras el recorrido de pago de prueba completo.

1. **Activa la cuenta** de Stripe para cobrar (datos del negocio y cuenta bancaria). Hasta entonces, el modo real no funciona.
2. **Productos y precios reales.** Los IDs del modo prueba no existen en el modo real. Crea Básico, Pro y Empresa con los
   seis precios de la tabla de arriba y los mismos `lookup_key` (`draxuvo_<plan>_<monthly|annual>`), en MXN, recurrentes y
   sin IVA incluido (`tax_behavior: exclusive`). Como la API busca por `lookup_key`, no hay IDs que cambiar en ningún lado.
3. **Clave restringida real** (`rk_live_…`) con los mismos permisos: Write en Customers, Checkout Sessions, Subscriptions y
   Customer portal; Read en Prices; todo lo demás en None. Cópiala directo en Render, no la pegues en chats ni archivos.
4. **Customer Portal real** (Settings → Billing → Customer portal, ya en modo real): método de pago, historial de facturas,
   cancelar al final del periodo y cambiar de plan con los seis precios y prorrateo.
5. **Webhook real:** endpoint `https://api.draxuvo.com/api/v1/stripe/webhooks` con los seis eventos de arriba. Su secreto
   `whsec_…` es distinto al del modo prueba.
6. **Render:** cambia `STRIPE_API_KEY` por la `rk_live_…` y `STRIPE_WEBHOOK_SECRET` por el secreto del webhook real, en un
   solo guardado (dispara un despliegue).
7. **Prueba con dinero real:** una suscripción del plan más barato con tu tarjeta, confirma que el webhook responde 2xx y la
   suscripción queda `active`; después cancélala y reembolsa desde el panel.
8. El webhook y las claves de prueba siguen existiendo en el sandbox; no estorban. Para volver a probar sin riesgo,
   vuelve a poner las claves de prueba en Render.

## Suspensión por falta de pago (spec 031)

- **Cambio de plan facturado al momento**: en *Settings → Billing → Customer portal → Subscriptions → Update*, usa `Always invoice` como prorrateo. Así un cambio de plan genera al instante una factura con `billing_reason = subscription_update`; si no se paga, `invoice.payment_failed` suspende a la empresa de inmediato. Un cobro de renovación fallido (`subscription_cycle`) deja `past_due` con 7 días de gracia.
- **Portal sin cambio de plan para la prueba**: crea una segunda configuración del portal con *Update subscriptions* apagado y pon su id (`bpc_…`) en `STRIPE_PORTAL_TRIAL_CONFIGURATION`. Una empresa en prueba con suscripción de Stripe (pagó por adelantado) abre el portal con esa configuración; sin ella el portal responde 422.
- **Reloj**: `Subscriptions::EnforceJob` (cada hora, `config/recurring.yml`) suspende las `past_due` con más de 7 días, avisa a los 23 días de suspendida y cancela (Stripe y local) a los 30 días.
