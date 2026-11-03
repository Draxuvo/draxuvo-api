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

## Módulos extra (spec 050 y 053)

> Desde la spec 053 el cliente no contrata el extra: solo el super admin lo enciende y apaga por empresa desde la hoja «Módulos» de `/empresas`. Los endpoints de abajo requieren super admin y la empresa va en `X-Company-Id`.

Un módulo extra se cobra como un segundo renglón de la suscripción del plan. Crea un producto «Punto de venta» en MXN con dos Prices recurrentes y sin IVA, igual que los planes:

| Módulo | Mensual | `lookup_key` mensual | Anual | `lookup_key` anual |
|---|---|---|---|---|
| Punto de venta (`pos`) | 199.00 | `draxuvo_addon_pos_monthly` | 1,990.00 | `draxuvo_addon_pos_annual` |

Los montos tienen que coincidir con `app/models/addon.rb`. Cómo se comporta:

- **Encender** (`POST /api/v1/subscription/addons`, super admin): la API agrega el renglón a la suscripción con el ciclo del plan (un Stripe no mezcla intervalos), `proration_behavior: always_invoice` y `payment_behavior: error_if_incomplete`. Se cobra al instante la parte proporcional del periodo con IVA (la tasa predeterminada de la suscripción ya aplica al renglón nuevo). Si el cobro falla, Stripe rechaza el alta, la API responde 402 `addon_payment_failed` y el módulo no se activa.
- **En prueba**: el super admin lo enciende sin cobro y sin renglón de Stripe; el checkout lo suma como segundo `line_item` al primer pago del plan. Apagarlo en prueba lo quita al instante.
- **Sin Prices no se enciende**: mientras no existan los dos Prices, la API responde 422 `addon_not_available` y la hoja lo explica.
- **Baja** (`DELETE /api/v1/subscription/addons/pos`): la API quita el renglón con `proration_behavior: none` (sin reembolso) y deja el acceso hasta el fin del periodo ya pagado (`subscription_addons.ends_at`). La siguiente factura ya no lo trae.
- **Reactivar** antes del fin: vuelve a agregar el renglón sin cobrar de nuevo.
- **Sincronización**: `Subscriptions::SyncService` lee todos los renglones de la suscripción; el que trae un `lookup_key` de plan define plan y ciclo y los de `draxuvo_addon_*` definen los extras. Un cambio de plan en el portal conserva el extra.

**Customer Portal**: el portal debe permitir cambiar de plan sin quitar el extra. En *Settings → Billing → Customer portal → Subscriptions*, deja el producto «Punto de venta» fuera de los productos intercambiables y sin cancelación de renglón individual: el extra lo apaga el super admin en Draxuvo, no el cliente desde el portal. Verifícalo en modo prueba antes de publicar (tarea T060 de la spec 050).

## Tasa de IVA

Los precios van sin IVA y Stripe suma el IVA aparte (spec 042). En cada cuenta de Stripe (prueba y real) crea una sola tasa de impuesto en *Product catalog → Tax rates*:

| Campo | Valor |
|---|---|
| Nombre | `IVA` |
| Porcentaje | `16` |
| Tipo | No incluido en el precio (*exclusive*) |
| País | México |
| Metadata | `draxuvo_tax` = `iva_16` |

La API la encuentra por esa metadata (no hay ID en variables de entorno) y la guarda en cache una hora. Al crear el checkout la pone como tasa predeterminada de la suscripción, por lo que **las renovaciones y los cambios de plan del Customer Portal la heredan** y la factura muestra el IVA como renglón aparte. Si la tasa no existe, el checkout responde 400 `stripe_not_configured` y no crea la sesión: es preferible no cobrar a cobrar sin IVA. Las suscripciones creadas antes de esta corrección no la tienen.

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
| `ADDON_POS_ENABLED` | `true` por omisión. En producción el módulo extra «Punto de venta» solo se ofrece (`GET /plans`, Suscripción y el sitio público) si esta variable no es `false` **y** sus dos Prices existen en la cuenta de Stripe activa (spec 052); se revisa cada 5 minutos. Ponla en `false` para ocultarlo |
| `LOGIN_RATE_LIMIT` / `LOGIN_RATE_WINDOW_MINUTES` | Intentos de inicio de sesión por cuenta e IP (10) y ventana (15 minutos) antes del 429 (spec 052) |

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
   Los dos Prices del extra «Punto de venta» (`draxuvo_addon_pos_monthly|annual`, sección «Módulos extra») se crean igual; mientras
   no existan, la API no lo anuncia ni lo ofrece (spec 052). Crea también la **tasa de IVA** de la sección «Tasa de IVA»; sin ella el checkout no abre.
3. **Clave restringida real** (`rk_live_…`) con los mismos permisos: Write en Customers, Checkout Sessions, Subscriptions y
   Customer portal; Read en Prices y en Tax rates; todo lo demás en None. Cópiala directo en Render, no la pegues en chats ni archivos.
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
