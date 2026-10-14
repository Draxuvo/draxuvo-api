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
bin/rails routes              # Show all API routes
bin/rails console             # Interactive console
bin/rubocop                   # Lint (Rails Omakase style)
bin/brakeman                  # Security scan
```

Tests live in `test/models/` and `test/controllers/api/v1/`. All tests use fixtures (`test/fixtures/`). Parallel execution is enabled by default.

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
| `WorkOrder` | Core work entity; statuses: `pending → in_progress → in_review → completed → cancelled`; priorities: `low/medium/high/urgent` |
| `WorkOrderItem` | Checklist items on a work order; ordered by `position`; `subtotal = unit_price * quantity` |
| `Ticket` | Auto-generated via `after_commit` when a WorkOrder transitions to `completed` and has no ticket yet; folio format `T-000001`; statuses: `pending/paid`; `mark_as_paid` endpoint |
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
- `app/services/users/` — user-related logic
- `app/services/products/` — `ImportService` for Excel import (roo); template download uses caxlsx
- `app/services/subscriptions/` — `CreateCheckoutService`, `PriceLookupService`, `SyncService`, `PortalService`, `CancelService`, `HandleWebhookService`

**Error classes** (`app/errors/api_errors.rb`): `ApiErrors::BadRequestError`, `UnauthorizedError`, `ForbiddenError`, `NotFoundError`, `UnprocessableEntityError` — all inherit `BaseError` and render `{ error: { status, message, details } }`.

**i18n**: Default locale is Spanish (`es`). Error messages and domain labels (work order status/priority, ticket status) are all translated. Locales in `config/locales/es.yml` and `en.yml`.

### WorkOrder → Ticket lifecycle

When a `WorkOrder` status changes to `completed`, an `after_commit` callback calls `generate_ticket!` if no ticket exists yet. The `Ticket` copies the work order `total`, reserves a temp folio UUID, then overwrites it with `T-000001` format in an `after_create` callback. `Ticket#download` renders via `Pdf::TicketPdfService`.

### Subscription & Stripe

Any plan and cycle goes through a Stripe Checkout Session (`Subscriptions::CreateCheckoutService`); prices are resolved by `lookup_key` `draxuvo_<plan>_<cycle>`. Stripe sends webhooks to `POST /api/v1/stripe/webhooks` (no JWT, signature always required): `HandleWebhookService` records each event in `StripeEvent` (idempotent) and `SyncService` re-reads the subscription from Stripe. Plan changes, card, invoices and cancel happen in the Stripe Customer Portal (`POST /subscription/portal`). Setup: `docs/stripe.md`.

### Background Jobs & Caching

Uses Rails 8 defaults: **Solid Queue** for jobs, **Solid Cache** for caching, **Solid Cable** for ActionCable. Production uses separate databases for primary, cache, queue, and cable — all configured from `DATABASE_URL`.

### File Storage

Active Storage; dev uses local disk. Production supports Cloudinary or S3-compatible (AWS, Backblaze, Supabase) via env vars. `WorkOrder` uses `has_many_attached :attachments`.

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
