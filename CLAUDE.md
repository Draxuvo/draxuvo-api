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

`AuthenticationController` inherits `ApplicationController` directly (not `BaseController`) since login is public. Login auto-creates an attendance checkin for the day if the user has an associated `Employee` and hasn't checked in yet.

`UploadsController` also inherits `ApplicationController` directly (skips auth); it manages Active Storage blobs for images (max 10 MB, jpeg/png/gif/webp/svg).

`SubscriptionsController` skips the `check_subscription!` before_action so users with expired subscriptions can still access billing.

### Domain Model

| Entity | Notes |
|---|---|
| `User` | Roles: `staff`, `manager`, `admin`, `owner`, `super_admin`; uses `has_secure_password` |
| `Company` | Tenant container; holds `stripe_id` and `disabled_modules`; `active_modules` = its plan's modules minus the disabled ones. No plan column: the plan lives in `Subscription` |
| `Employee` | Company staff; optional `user` association; `parsed_name_parts` splits `name` for User creation |
| `Plan` | PORO catalog (`app/models/plan.rb`): `basic`, `pro`, `enterprise` with their modules and monthly/annual prices (cents MXN, without IVA) |
| `Subscription` | One per Company (unique); plan `basic/pro/enterprise`, `billing_cycle`, `cancel_at_period_end`; statuses: `trialing/active/past_due/cancelled/expired`; `active_access?` returns true for trialing (within trial), active, or past_due |
| `WorkOrder` | Core work entity; statuses: `open → in_progress → done → paid`, or `cancelled` (ints 0 to 4); changes only through `WorkOrders::Transition` (`start/finish/reopen/charge/cancel/void_charge`); customer fields; priorities `low/medium/high/urgent`. `paid` and `cancelled` are locked |
| `WorkOrderItem` | Billable concept of an order (no status); `subtotal = unit_price * quantity`. The to-do checklist is `WorkOrderStep`; history is `WorkOrderEvent` (insert only); photos are `WorkOrderAttachment` |
| `Ticket` | One per order, created or reused inside the `charge` transaction; folio `T-000001`; statuses `pending/paid/voided`; holds the charge summary (method or `mixed`, received, change, who charged, void data) |
| `TicketPayment` | One payment of an order charge (spec 015): `cash/card/transfer`, amount; cash keeps received and change, card an optional terminal, authorization and last 4, transfer a required reference; `source` (`manual`). Never edited: voiding the charge sets `voided_at` and the next charge reuses the ticket and folio with new payments |
| `PaymentTerminal` | A business card terminal (spec 015): name unique per company, `provider` from `PaymentTerminal::PROVIDERS` (banks, Mercado Pago, Clip, other), `active`. Admin and owner manage them in `/payment_terminals`; one with payments is deactivated, not deleted. Draxuvo does not connect to them yet |
| `Station`, `DiningTable`, `Check`, `KitchenOrder`, `CheckItem`, `CheckPayment` | Restaurant module (`restaurant`, Pro and Enterprise): a check (`open/closed/cancelled`) belongs to a table or a takeout name; items go `draft → new → preparing → ready → delivered` (or `cancelled`) and each belongs to the station of its product; a kitchen order is one batch sent at once. Rules live in `app/services/restaurant/` (`SendRound`, `AdvanceItems`, `CancelItem`, `AddPayment`, `CloseCheck`, `Availability`, `Permissions`). Closing a check creates a `Ticket` with `check_id` (payment method `mixed` when it was paid with several) and deducts `Product#tracks_stock` inventory. Controllers live in `Api::V1::Restaurant` (always write `::Restaurant::` inside `Api::V1` so the service module is not shadowed) |
| `Company#order_mode` | `service` (default) or `order`; changed by the owner with `PATCH /company/order_mode` |
| `Product` | Inventory item with `StockMovement` sub-resource; has `menu` collection route; supports Excel import/export |
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
