# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
bin/rails server              # Start dev server on port 3000
bin/rails test                # Run all tests (parallel, uses fixtures)
bin/rails test test/models/user_test.rb          # Run a single model test
bin/rails test test/controllers/api/v1/users_controller_test.rb  # Run a controller test
bin/rails db:migrate          # Run pending migrations
bin/rails db:seed             # Seed the database
bin/rails db:reset            # Drop, recreate and reseed (regenerates demo data, development only)
bin/rails routes              # Show all API routes
bin/rails console             # Interactive console
bin/rubocop                   # Lint (Rails Omakase style)
bin/brakeman                  # Security scan
```

Tests live in `test/models/`, `test/services/` (one file per service), `test/controllers/api/v1/` and `test/lib/`. All tests use fixtures (`test/fixtures/`, coherent data, no scaffold). Parallel execution is enabled by default, so a test that touches global state restores it: use the `test/support` helpers (`with_env`, `with_memory_cache`, `stripe_sub_hash`, `with_checkout_stubs`, `with_cancel_stubs`). Third parties are stubbed with Minitest `stub` (no mocha/webmock/vcr). Brakeman's one accepted warning (Rails 8.0.2 end of support) lives in `config/brakeman.ignore` and expires 2026-11-07.

## Architecture

**Rails 8.0.2 API-only**, Ruby 3.4.4, PostgreSQL. A multi-tenant ERP system for managing employees, work orders, inventory, and invoicing.

### Multi-Tenancy

Every request must include `X-Company-Id` header. `BaseController#current_company` resolves the tenant from this header and scopes all queries to it. Users belong to companies via the `user_companies` join table.

### API Namespace

All endpoints live under `/api/v1/`. The base controller (`app/controllers/api/v1/base_controller.rb`) handles:
- JWT authentication via `Authorization: Bearer <token>` — decoded with `SECRET_KEY_BASE` (HS256, 24h expiry)
- Company scoping (multi-tenant context)
- Subscription gate via `check_subscription!` — auto-starts a 30-day Pro trial if none exists; blocks if expired/cancelled
- Module gate via the `ModuleGate` concern: `requires_module :inventory` in a controller returns 403 `module_not_in_plan` when the company's plan doesn't include it
- Standardized error handling via `rescue_from` with `ApiErrors` module in `app/errors/api_errors.rb`
- Sorting via `apply_sort(scope, allowed: %i[...])` — only allowlisted columns accepted
- Pagination via Pagy (`limit` param, max 100); use `paginate_response(@pagy, serialized)` in controllers

The `Authenticable` and `Authorizable` concerns live in `app/controllers/concerns/`. `Authorizable` provides:
- `require_super_admin!` — super_admin only
- `require_admin!` — admin, owner, or super_admin

`AuthenticationController` inherits `ApplicationController` directly (not `BaseController`) since login is public. Login no longer creates attendance (spec 026): the user marks it with `Api::V1::MyAttendanceController` (`/my_attendance/today|check_in|check_out`, logic in `Attendances::Mark`).

`UploadsController` also inherits `ApplicationController` directly (skips auth); it manages Active Storage blobs for images (max 10 MB, jpeg/png/gif/webp/svg).

`SubscriptionsController` skips the `check_subscription!` before_action so users with expired subscriptions can still access billing.

### Domain Model

| Entity | Notes |
|---|---|
| `User` | Roles: `staff`, `admin`, `owner`, `super_admin`; uses `has_secure_password` |
| `Company` | Tenant container; holds `stripe_id` and `disabled_modules`; `active_modules` = its plan's modules minus the disabled ones. No plan column: the plan lives in `Subscription`. Only the super admin changes `disabled_modules` (`PATCH /company/modules` with `X-Company-Id`, 403 for any other role, spec 017); each change of state is logged in `ModuleChange` (company, actor, module, enabled, created_at; no screen) |
| `Employee` | Company staff; optional `user` association; `parsed_name_parts` splits `name` for User creation |
| `Plan` | PORO catalog (`app/models/plan.rb`): `basic`, `pro`, `enterprise` with their modules and monthly/annual prices (cents MXN, without IVA) |
| `Subscription` | One per Company (unique); plan `basic/pro/enterprise`, `billing_cycle`, `cancel_at_period_end`; statuses: `trialing/active/past_due/cancelled/expired/suspended`; `active_access?` returns true for trialing (within trial), active, or past_due and false for `suspended` (spec 031: a plan change whose invoice is not paid, or a renewal unpaid after 7 days, blocks the company with 403 `subscription_suspended`; `Subscriptions::EnforceJob` cancels it after 30 days; changes are logged in `SubscriptionChange`). During the trial only the super admin changes the plan (`PATCH /subscription` gives 403 `trial_plan_locked` to owner and admin) |
| `WorkOrder` | Core work entity; statuses: `open → in_progress → done → paid`, or `cancelled` (ints 0 to 4); changes only through `WorkOrders::Transition` (`start/finish/reopen/charge/cancel/void_charge`); customer fields; priorities `low/medium/high/urgent`. `paid` and `cancelled` are locked |
| `WorkOrderItem` | Billable concept of an order (no status); `subtotal = unit_price * quantity`. The to-do checklist is `WorkOrderStep`; history is `WorkOrderEvent` (insert only); photos are `WorkOrderAttachment` |
| `Ticket` | One per order, created or reused inside the `charge` transaction; folio `T-000001`; statuses `pending/paid/voided`; holds the charge summary (method or `mixed`, received, change, who charged, void data) |
| `TicketPayment` | One payment of an order charge (spec 015): `cash/card/transfer`, amount; cash keeps received and change, card an optional terminal, authorization and last 4, transfer a required reference; `source` (`manual`). Never edited: voiding the charge sets `voided_at` and the next charge reuses the ticket and folio with new payments |
| `PaymentTerminal` | A business card terminal (spec 015): name unique per company, `provider` from `PaymentTerminal::PROVIDERS` (banks, Mercado Pago, Clip, other), `active`. Admin and owner manage them in `/payment_terminals`; one with payments is deactivated, not deleted. Draxuvo does not connect to them yet |
| `Station`, `DiningTable`, `Check`, `KitchenOrder`, `CheckItem`, `CheckPayment` | Restaurant module (`restaurant`, Pro and Enterprise): a check (`open/closed/cancelled`) belongs to a table or a takeout name; items go `draft → new → preparing → ready → delivered` (or `cancelled`) and each belongs to the station of its product; a kitchen order is one batch sent at once. Rules live in `app/services/restaurant/` (`SendRound`, `AdvanceItems`, `CancelItem`, `AddPayment`, `CloseCheck`, `Availability`, `Permissions`, `TableState`, `ServiceOverview`). `Station#kind` (`kitchen|bar|other`) gives the station screen its identity; `GET /restaurant/tables` adds `state` per table (`free|occupied|to_pay`) and, for bosses only, `overview`, while a waiter gets no `total`/`waiter` on other people's checks. `ProductType#in_menu` (scope `Product.on_menu`) filters `GET /products/menu` only in order-mode companies and makes `POST …/checks/:id/items` answer 422 `not_on_menu`. Closing a check creates a `Ticket` with `check_id` (payment method `mixed` when it was paid with several) and deducts `Product#tracks_stock` inventory. Controllers live in `Api::V1::Restaurant` (always write `::Restaurant::` inside `Api::V1` so the service module is not shadowed) |
| `Company#order_mode` | `service` (default) or `order`; changed by the owner with `PATCH /company/order_mode` |
| `Product` | Inventory item with `StockMovement` sub-resource; has `menu`, `by_code` and `export` collection routes; has many `ProductBarcode` (unique per company, exact text; `search` also matches them; `replace_barcodes!` for the form, imports only add). Excel import (columns include `tipo`, `unidad` and `barcodes`) runs in the background: `POST /products/import` creates a `ProductImport` (file kept in `file_data` until done) and enqueues `Products::ImportJob`, which runs `Products::ImportService` in batches of 200 (preloaded lookups, barcodes with one `insert_all`, stock changes through `Stock::RecordMovements`, which writes movements in bulk with the user and updates stock in one statement); `Stock::Receive` (goods receipt, all or nothing) and `Stock::ConfirmCount` (physical count `StockCount`/`StockCountItem`, adjusts against current stock) share it. Belongs to a `ProductType`; `stock`, `min_stock` and movement `qty` are decimal(12,3) but only fractional types accept fractions. `tracks_stock` is synced from the type (the restaurant reads it). Scopes `sellable` (menu, checks, order catalog) and `low_stock` (counted type, `min_stock > 0`, `stock <= min_stock`) are the only rules for "se vende" and "bajo inventario"; JSON quantities go through `Product.quantity` (numbers, never strings) |
| `ProductType` | Per-company product type (spec 016): `name`, `sellable`, `counted`, `fractional`, `default_unit_key`, `active`. `ProductTypes::Defaults` creates the initial ones by `order_mode` (Platillo/Bebida/Insumo or Servicio/Refacción/Material) on company creation and classifies products without a type. Admin/owner manage them in `/product_types` (with `move_products`); one with products is deactivated, not deleted |
| `Attendance` | Check-in/out records; types: `normal/late/absent` |
| `Unit` | Measurement units for products |
| Dashboard | `GET /api/v1/dashboard` — aggregate stats for employees, users, work orders, tickets, inventory, and attendance (today + month) |

### Key Patterns

**Controllers**: inherit `BaseController`, call `apply_sort` then `pagy`, then `paginate_response`. Multi-step writes go in transactions. `base_scope` private method returns the company-scoped relation used in all actions.

**Serializers** (`app/serializers/`) are plain Ruby classes with `initialize(record, detailed: false)` and `as_json`. Pass `detailed: true` for full nested data (e.g., `WorkOrderSerializer` includes items array only when detailed). Most index actions use Active Model Serializers directly; work orders and tickets use the plain-class serializers.

**Email**: Transactional email is sent via `ResendMailer` (`app/mailers/resend_mailer.rb`), a plain Ruby class (not ActionMailer) that calls the Resend API directly. Do NOT use ActionMailer or `deliver_later` for these emails. Service objects in `app/services/email/` (`SetPasswordService`, `PasswordResetService`) wrap `ResendMailer`.

**Employee → User auto-creation**: When creating an `Employee` with a non-blank `email`, `EmployeesController#create` automatically creates a `User` (via `parsed_name_parts`), links it via `user_companies`, and calls `Email::SetPasswordService` to send a set-password email. The user starts with `active: false`.

**Password flows** (`PasswordsController`, inherits `BaseController`):
- `PUT /passwords/update` — requires current password; changes password for authenticated user
- `POST /passwords/reset` — sends password-reset email (token-based); public via `Email::PasswordResetService`
- `PUT /passwords/update_with_token` — sets new password using reset token

**Company routing**: `resource :company` (singular) — scoped to current company; `resources :companies` (plural) — global CRUD, super_admin only.

**Services** are organized into subdirectories:
- `app/services/pdf/` — `TicketPdfService` generates Prawn A4 PDF
- `app/services/email/` — `SetPasswordService`, `PasswordResetService` (wrap `ResendMailer`)
- `app/services/users/` — `SyncMemberships`: the super admin's `POST/PATCH /users` send `memberships: [{ company_id, role }]` (the full final list, role per company); same rules as `/company/members` (no `super_admin`, never remove or demote a company's last owner). `users.role` is not written there (spec 014)
- `app/services/products/` — `ImportService` for Excel import (roo); template download uses caxlsx
- `app/services/work_orders/` — `Transition` (state changes) and `ChargePayments` (spec 015): `charge` takes `payments: [{ method, amount, amount_received, terminal_id, authorization_code, card_last4, reference }]` (at most one cash, which covers the rest and gives change; card and transfer never exceed the total) and still accepts the old `payment_method` + `amount_received` for installed apps. Staff create their own orders (assigned to their employee, catalog products only) and change quantities or remove items of their orders
- `app/services/subscriptions/` — `CreateCheckoutService`, `PriceLookupService`, `SyncService`, `PortalService`, `CancelService`, `HandleWebhookService`

**Error classes** (`app/errors/api_errors.rb`): `ApiErrors::BadRequestError`, `UnauthorizedError`, `ForbiddenError`, `NotFoundError`, `UnprocessableEntityError` — all inherit `BaseError` and render `{ error: { status, message, details } }`.

**i18n**: Default locale is Spanish (`es`). Error messages and domain labels (work order status/priority, ticket status) are all translated. Locales in `config/locales/es.yml` and `en.yml`.

### WorkOrder → Ticket lifecycle

`WorkOrders::Transition` (`app/services/work_orders/`) validates origin state and role, then saves the change, the event and, for `charge`, the ticket in one transaction (no `rescue`: if the ticket fails, nothing is charged). `void_charge` (owner/admin, with reason) leaves the ticket `voided` and the order `done`; charging again reuses the same ticket and folio. Staff only see and act on orders assigned to their employee **in the active company** (`current_employee`); `WorkOrderSerializer` returns `allowed_actions` per role and state, and the UI only draws those.

### Subscription & Stripe

Any plan and cycle goes through a Stripe Checkout Session (`Subscriptions::CreateCheckoutService`); prices are resolved by `lookup_key` `draxuvo_<plan>_<cycle>`. Stripe sends webhooks to `POST /api/v1/stripe/webhooks` (no JWT, signature always required): `HandleWebhookService` records each event in `StripeEvent` (idempotent) and `SyncService` re-reads the subscription from Stripe. Plan changes, card, invoices and cancel happen in the Stripe Customer Portal (`POST /subscription/portal`). Setup: `docs/stripe.md`.

### Background Jobs & Caching

Uses Rails 8 defaults: **Solid Queue** for jobs, **Solid Cache** for caching, **Solid Cable** for ActionCable. Production uses a single database (`DATABASE_URL`): the Solid tables live in the primary schema (migration `create_solid_tables`). Solid Queue runs inside Puma when `SOLID_QUEUE_IN_PUMA` is set (it is in `render.yaml`).

### Barcodes & labels (spec 035)

`Barcodes::Generator` (`app/services/barcodes/`) reserves own codes: `"29"` + 10-digit sequence + EAN-13 check digit (`Barcodes::CheckDigit`); the sequence is advanced with one atomic `UPDATE … RETURNING` inside `Company.uncached` (the query cache would otherwise repeat blocks) and codes already in `product_barcodes` are skipped. `Labels::Catalog` loads the common formats from `config/label_formats.yml` (ids `std:<key>`); own formats are `LabelFormat` rows (max 20 per company, grid must fit the page). `Labels::PdfService` (Prawn, AFM Helvetica with Windows-1252 sanitization) draws with `Labels::Layout` (mm→pt, start position) and `Labels::BarcodeDrawing` (gem `barby`: EAN-13, EAN-8 or Code 128 chosen from the value; module 0.33 mm, never below 0.264 mm); `check` returns count, pages, warnings (`code_too_small`, `content_too_big`) and skipped products without building the file. Geometry tests read the uncompressed PDF (`test/support/label_pdf_helpers.rb`).

### File Storage

Active Storage; dev uses local disk. Production supports Cloudinary or S3-compatible (AWS, Backblaze, Supabase) via env vars. Order photos are `WorkOrderAttachment` (`has_one_attached :file`; images only, 10 MB, 10 per order).

### Deployment

Dockerized with Kamal for orchestration. Also has `render.yaml` for Render.com deployment. Health check at `/up`.

## Environment Variables

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | Production DB connection |
| `RAILS_MASTER_KEY` | Credentials decryption |
| `SECRET_KEY_BASE` | JWT signing key |
| `RESEND_API_KEY` / `RESEND_FROM_EMAIL` | Transactional email |
| `FRONTEND_URL` | CORS allowed origin (default: `http://localhost:4200`) |
| `STRIPE_API_KEY` / `STRIPE_WEBHOOK_SECRET` | Stripe secret key and webhook signing secret |
| `APP_HOST` / `ALLOWED_HOSTS` | Public host for links and extra allowed hosts in production |
| Cloud storage keys | Cloudinary or S3-compatible credentials |

### Demo por plan (spec 039)

Cada visita crea una empresa efímera con `companies.demo = true` (`Demo::Provision`), un dueño efímero y los datos de uno de cuatro
escenarios deterministas (`app/services/demo/scenarios/`: `basic_retail`, `pro_service`, `pro_restaurant`, `enterprise_restaurant`).
`Demo::Purge` la borra por completo (sucursales y cuentas primero) y `Demo::PurgeJob` corre cada 10 minutos; la apertura
(`demo_sessions`) sobrevive para el seguimiento comercial. `Current.demo` (que `BaseController` activa según `X-Company-Id`) hace que
`ResendMailer`, `Whatsapp::*` y `Subscriptions::*` simulen o bloqueen todo efecto externo (`Demo::Guard`). Las demos se excluyen de las
listas y métricas del super admin (`Company.real`, `User.real`). Límites: `DEMO_RATE_LIMIT`, `DEMO_MAX_ACTIVE`,
`DEMO_MAX_PROVISIONING`, `DEMO_TTL_MINUTES` y `DEMO_INVITE_DAYS`. `bin/rails demo:benchmark` mide cuánto tarda cada escenario (objetivo: 5 s).

### Alertas operativas (spec 045)

Dueño y administrador (`require_boss!`) ven lo que pide atención. **Las alertas no se guardan**: `Alerts::Collector` las arma al leer
(`GET /alerts`, paginado con `{ info, results }` más `count` y `snoozed`) con una fuente por tipo en `app/services/alerts/sources/`
(`KitchenWait`, `KitchenPreparing`, `WorkOrderStalled`, `TableOpen`, `LowStock`; cada una declara su `module_key`, y un tipo con el módulo apagado
no se evalúa). Los límites salen de `AlertSetting` (`thresholds` anidado, solo lo que el negocio cambió; comandas por `Station#kind`);
`POST/DELETE /alerts/snooze` pospone 30, 60 o 120 min (`AlertSnooze`, `low_stock` no se pospone; la `subject_key` lleva el origen del
elemento y la posposición se borra al leer si el elemento avanzó). `GET/PATCH /alert_settings` y `/notification_preference`
(`NotificationPreference` por persona y empresa). Stock bajo: `StockAlerts::ScanJob` (cada 5 min) detecta con `Scan`, espera
`StockAlertState::GRACE` y manda agrupado con `Dispatch`/`Notify`; `DailySummaryJob` (cada hora) manda el resumen a la hora local de la empresa;
`Alerts::Recipients` decide a quién (solo por correo); cada envío queda en `AlertDelivery`. Correo: `ResendMailer.stock_alert`. **Desde la spec 048
el stock bajo ya no sale por WhatsApp** (se borró `Whatsapp::StockAlertService`): solo correo y alerta del panel y de la app; `NotificationPreference.stock_whatsapp`,
las filas `alert_deliveries` con canal `whatsapp` y los `whatsapp_events` del tipo retirado se conservan como historial pero ya no se leen ni se escriben
(`GET/PATCH /notification_preference` solo habla de `stock_email` y ignora `stock_whatsapp`). Demos y empresas sin acceso no mandan nada (`StockAlerts::Companies`).

### Configurar WhatsApp (spec 047)

El super admin conecta WhatsApp Business desde el panel (`/whatsapp` en `ui`); todo vive bajo `/api/v1/whatsapp`, **sin `X-Company-Id` y solo para el super admin**
(`WhatsappAccess` concern: `require_super_admin!` y `StaleObjectError` → 409 `stale_object` con el estado vigente en `details.current`). Controladores en
`Api::V1::Whatsapp::` (`ConnectionsController`, `ChannelsController`, `MessageTypesController`, `EventsController`) más `WhatsappController` (`show`, `guide`).
**Dentro de `Api::V1` escribe `::Whatsapp::`**: el módulo `Api::V1::Whatsapp` de los controladores sombrearía a los servicios.

- **Tablas**: `whatsapp_connections` (una sola fila; `access_token` cifrado con ActiveRecord::Encryption y claves derivadas de `SECRET_KEY_BASE` en
  `config/initializers/active_record_encryption.rb`, `token_hint` con los últimos 4, `status` `not_connected|connected|error`, `managed`, `enabled`,
  `problem_notified_at`, `lock_version`), `whatsapp_message_types` (`verification_code` y `ticket`; el tipo `stock_alert` se retiró en la spec 048: su fila se conserva apagada y `ensure_all!` ya no la crea ni la devuelve; plantilla, idioma, estado, `enabled`) y
  `whatsapp_events` (solo inserción; `WhatsappEvent.log!` borra de `data` cualquier clave secreta y los teléfonos van con `mask_phone`). La llave jamás se
  serializa: `WhatsappConnection#serializable_hash` la excluye y la API solo da `token_present` y `token_hint`.
- **`Whatsapp::Config`** es lo único que consultan los servicios de envío: `source` (`:panel` si `managed`, `:env` si el panel nunca se usó y hay `WHATSAPP_*`,
  `:none`), `available?(kind)` (conexión válida, interruptor general, interruptor del tipo y plantilla aprobada; los tickets no usan plantilla),
  `template_for`, `client`. El panel manda sobre las variables incluso tras desconectar.
- **`Whatsapp::GraphClient`** es la única salida a Meta (timeouts 3 s/5 s) y clasifica los errores en familias `connection`, `template`, `recipient`,
  `transient` y `other` (`Failure#user_message`). `ConnectionCheck`, `TemplateCheck`, `TemplateVerification` y `TestMessage` solo leen o mandan con ese cliente;
  Draxuvo **no crea plantillas** en Meta.
- **`Whatsapp::Health`** cambia estados con los fallos y éxitos reales (`record_failure`, `record_success`, `connection_recovered!`, `template_recovered!`,
  `template_unusable!`): conexión → «Con error» (los interruptores no se tocan y el canal se reanuda al recuperarse), plantilla → se apaga **solo ese tipo**
  (hay que volver a encenderlo a mano). Un correo por **cambio de estado** (`problem_notified_at`) a los super admin activos con `ResendMailer.whatsapp_alert`.
  Los fallos de destinatario o de red no cambian nada.
- **No hay revisión periódica**: se verifica al guardar, con «Verificar ahora» y antes de cada mensaje de prueba. Pruebas: 5 por hora por super admin
  (`Whatsapp::TestLimit`, contadas con los eventos `test_sent`, 429).
- **Pruebas**: Meta se simula con `Net::HTTP.stub(:new, …)` (los `FakeHttp` necesitan `open_timeout`); ninguna prueba llama a la red real. Si rotas `SECRET_KEY_BASE`
  en producción la llave guardada queda ilegible (la conexión pasa a «Con error»). Despliegue y pasos de Meta: `docs/deploy.md`.
