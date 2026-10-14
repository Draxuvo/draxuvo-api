# Ideas de Valor para Draxuvo API

## Estado actual del producto (abril 2026)

El ERP multi-tenant cubre: autenticación JWT, empresas, usuarios/empleados, asistencias, productos + inventario, órdenes de trabajo, tickets con PDF, suscripciones Stripe, WhatsApp (OTP + envío de tickets), reportes financieros básicos y dashboard. La última iteración cerró: perfil de usuario, avatar, y verificación de teléfono vía OTP WhatsApp.

---

## Tier 1 — Desbloqueadores de ingresos (alto impacto, esfuerzo medio)

### 1. Facturación CFDI 4.0 (México)

**Problema:** El `Ticket` solo genera un PDF interno. Los clientes B2B en México necesitan factura fiscal válida; sin esto no puedes vender a empresas medianas/grandes.

**Propuesta:**

- Modelo `Invoice` (belongs_to `Ticket`, `Customer`, `Company`): `uuid`, `xml`, `pdf`, `status`, `uso_cfdi`, `forma_pago`, `metodo_pago`.
- Campos fiscales en `Company` (emisor): `rfc`, `razon_social`, `regimen_fiscal`, `cp_fiscal`.
- Campos SAT en `Product`: `clave_prod_serv`, `clave_unidad`, `objeto_impuesto`.
- Servicio `Invoicing::FacturamaService` (Facturama API es la más rápida; alternativas: SW Sapien, Prontipagos).
- Endpoints: `POST /tickets/:id/invoice`, `GET /invoices/:id/xml`, `GET /invoices/:id/pdf`, `POST /invoices/:id/cancel`.

**Archivos a crear/modificar:**

- `app/models/invoice.rb`, `app/models/customer.rb`
- `app/services/invoicing/facturama_service.rb`
- `app/controllers/api/v1/invoices_controller.rb`
- Migraciones: `create_customers`, `create_invoices`, `add_fiscal_fields_to_companies`, `add_sat_fields_to_products`

**Esfuerzo:** 2–3 semanas | **ROI:** Permite subir 30–50% el precio de planes Business/Enterprise.

---

### 2. Cobro de tickets (OXXO + SPEI + tarjeta)

**Problema:** `mark_as_paid` es manual hoy. Sin link de cobro directo se pierden ventas y la reconciliación es manual.

**Propuesta:**

- Stripe México con `payment_method_types: [card, oxxo]` (ya tienes cuenta) o MercadoPago (mayor cobertura SPEI/OXXO MX).
- Endpoint `POST /tickets/:id/payment_link` → genera Checkout Session, devuelve URL.
- Webhook: `checkout.session.completed` → `mark_as_paid` automático.
- Reutilizar `Whatsapp::TicketService` para enviar link por WhatsApp junto al PDF.

**Archivos a crear/modificar:**

- `app/services/payments/ticket_checkout_service.rb` (nuevo)
- `app/controllers/api/v1/tickets_controller.rb` (nuevo action `payment_link`)
- `app/services/subscriptions/handle_webhook_service.rb` (nueva rama para tickets)

**Esfuerzo:** 1–1.5 semanas | **ROI:** Reduce días-de-cobro, aumenta conversión.

---

### 3. Módulo Customer (CRM mínimo) — prerequisito de #1 y #2

**Problema:** No existe `Customer`. Los tickets no tienen cliente final, lo que bloquea CFDI, historial y cobranza.

**Propuesta:**

- Modelo `Customer` (belongs_to `Company`): `name`, `email`, `phone`, `rfc`, `tax_regime`, `cfdi_use_default`, `address`, `notes`.
- `WorkOrder` y `Ticket` agregan `customer_id` (nullable para backward compat).
- CRUD `/api/v1/customers` + `GET /customers/:id/tickets` (historial de órdenes).
- Búsqueda por nombre/teléfono/RFC con ILIKE.

**Archivos a crear:**

- `app/models/customer.rb` + `app/controllers/api/v1/customers_controller.rb`
- Migraciones: `create_customers`, `add_customer_to_work_orders_and_tickets`

**Esfuerzo:** 4–5 días | **ROI:** Habilitador de todo el Tier 1.

---

## Tier 2 — Retención y calidad operativa (impacto medio, esfuerzo bajo-medio)

### 4. Auditoría con `paper_trail`

**Problema:** No hay trazabilidad de quién cambió qué. Crítico para un ERP y requisito casi legal.

**Propuesta:** Gema `paper_trail`, `has_paper_trail` en `Ticket`, `WorkOrder`, `Product`, `Subscription`, `Invoice`. Endpoint `GET /tickets/:id/history`.

**Esfuerzo:** 1–2 días | **ROI:** Defensivo — evita disputas y problemas legales.

---

### 5. Notificaciones in-app + email configurable

**Problema:** Email transaccional limitado a 2 flujos (set/reset password). Eventos importantes (ticket pagado, stock bajo, orden asignada) pasan desapercibidos.

**Propuesta:**

- Modelo `Notification` (`user`, `kind`, `payload`, `read_at`).
- Broadcaster con Solid Cable (ya instalado pero sin uso de negocio).
- Emails para: ticket creado, ticket pagado, stock bajo, asistencia pendiente.
- `NotificationPreference` por usuario y canal (email / in-app / whatsapp).

**Esfuerzo:** 1.5 semanas | **ROI:** Mejora engagement diario y reduce "se me olvidó".

---

### 6. Exports PDF/Excel de reportes

**Problema:** `ReportsController` devuelve JSON; dueños y contadores necesitan Excel. Caxlsx y Prawn ya están instalados.

**Propuesta:** `GET /reports/summary.xlsx`, `/reports/income.xlsx`, `/reports/payroll.pdf`. Servicio `Reports::ExportService` con adapters por formato.

**Esfuerzo:** 3–4 días | **ROI:** Feature visible, fácil argumento de upsell.

---

### 7. Permisos granulares con Pundit

**Problema:** Solo existen `require_admin!` / `require_super_admin!`. Con múltiples sucursales por cliente el rol-enum no escala.

**Propuesta:** Gema `pundit`, policies por recurso, permisos por sucursal (requiere modelo `Branch`).

**Esfuerzo:** 1 semana (sin Branch), 2 semanas (con multi-sucursal) | **ROI:** Habilita contratos Enterprise.

---

## Tier 3 — Extensiones de producto (alto esfuerzo, alto techo)

### 8. Proveedores + Órdenes de Compra + Cuentas por Pagar

Completa el ciclo compra→inventario→venta→cobranza. Modelos `Supplier`, `PurchaseOrder`, `PurchaseOrderItem`, `AccountsPayable`. `StockMovement.entry` se liga a `PurchaseOrder`.

**Esfuerzo:** 3 semanas.

---

### 9. Nómina real (IMSS/ISR + CFDI nómina)

Hoy `Reports::PayrollService` solo calcula `salary × headcount`. Un módulo real: `PayrollRun`, retenciones, incidencias, vacaciones, finiquitos, recibos CFDI nómina.

**Esfuerzo:** 4–6 semanas | **Nota:** Evalúa si competir con Worky/Nominapp o integrarte vía webhook.

---

### 10. WhatsApp bidireccional (bot)

WhatsApp es solo salida hoy. Webhook de entrada permite: estados de tickets por chat, confirmación de citas, captura de leads.

**Esfuerzo:** 2 semanas MVP | **ROI:** Diferenciador fuerte en México.

---

### 11. Activar Cloud Storage en producción (riesgo activo)

Active Storage usa disco local en producción. Si el volumen se recicla, se pierden avatars, adjuntos de órdenes y plantillas. `config/storage.yml` ya tiene la config comentada para Cloudinary/S3.

**Esfuerzo:** 1 día | **ROI:** Defensivo crítico — hacerlo ya.

---

### 12. Webhooks salientes + API pública

Permitir que integradores reciban eventos: `ticket.paid`, `work_order.completed`. Modelo `WebhookEndpoint` con HMAC + API keys por tenant.

**Esfuerzo:** 1.5 semanas | **ROI:** Apertura para integraciones de partners.

---

## Orden recomendado (próximo trimestre)

| #   | Iniciativa            | Esfuerzo | Por qué ahora                       |
| --- | --------------------- | -------- | ----------------------------------- |
| 1   | Cloud Storage (#11)   | 1 día    | Riesgo activo de pérdida de datos   |
| 2   | Customer/CRM (#3)     | 4–5 días | Prerequisito de CFDI y cobros       |
| 3   | CFDI 4.0 (#1)         | 2–3 sem  | Desbloquea mercado B2B MX           |
| 4   | Cobro de tickets (#2) | 1.5 sem  | Monetización directa                |
| 5   | Auditoría (#4)        | 1–2 días | Bajo esfuerzo, alto valor defensivo |
| 6   | Exports (#6)          | 3–4 días | Quick win visible para usuarios     |

Con esto en ~6 semanas lanzas: facturación fiscal + cobro automático + CRM básico + blindaje de operación.

---

## Archivos de referencia actuales

- `app/controllers/api/v1/tickets_controller.rb` — base para iniciativas #1 y #2
- `app/services/subscriptions/handle_webhook_service.rb` — patrón webhook a reutilizar
- `app/services/whatsapp/ticket_service.rb` — patrón envío WhatsApp
- `app/services/pdf/ticket_pdf_service.rb` — patrón PDF (reutilizable en #6)
- `app/controllers/api/v1/reports_controller.rb` — extensible para #6
- `config/storage.yml` — config cloud comentada lista para #11
- `Gemfile` — agregar: `paper_trail` (#4), `pundit` (#7), `money-rails` (#1)

## El catálogo tiene 12 iniciativas en 3 tiers. Cuando quieras arrancar, mi recomendación es en este orden:

1. Cloud Storage (1 día) — riesgo activo hoy
2. Customer/CRM (4–5 días) — prerequisito de todo lo demás
3. CFDI 4.0 — el mayor desbloqueador de ingresos B2B en México

¿Por cuál empezamos?
