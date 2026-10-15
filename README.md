# draxuvo-api

API REST del ERP **Draxuvo**: multiempresa, con suscripciones y cobro. Rails 8 (solo API), Ruby 3.4.4 y PostgreSQL. Parte del [workspace Draxuvo](https://github.com/bothi3119/bothi).

## Qué hace

- **Empresas y equipo**: usuarios con roles por empresa (`staff` < `manager` < `admin` < `owner` < `super_admin`), miembros, sucursales y módulos activos por plan.
- **Operación**: empleados y asistencia, inventario con movimientos de stock e importación, órdenes de trabajo (servicio o pedido) con partidas, pasos, notas y fotos, tickets con PDF y envío por WhatsApp.
- **Cobro**: planes Básico, Pro y Empresa con prueba de 30 días, pago con Stripe Checkout y estado de la suscripción por webhooks.
- **Reportes**: dashboard, resumen, ingresos, gastos y nómina.

Todo vive bajo `/api/v1/`. La autenticación usa JWT (`Authorization: Bearer`) y cada petición lleva `X-Company-Id` para resolver la empresa. Referencia de endpoints: [`API_REFERENCE.md`](API_REFERENCE.md). Configuración de Stripe: [`docs/stripe.md`](docs/stripe.md).

## Empezar

Requiere Ruby 3.4.4 (ver `mise.toml`) y PostgreSQL con un rol que pueda crear bases.

```bash
cp .env.example .env     # llena SECRET_KEY_BASE y los datos de la base
bundle install
bin/rails db:prepare     # crea la base y carga semillas y datos de demo (solo en desarrollo)
bin/rails server         # http://localhost:3000, salud en /up
```

Los datos de demo son 5 empresas con usuarios `dueno@`, `admin@`, `manager@` y `staff@` en `donchuy.demo`, `volta.demo`, `sazon.demo`, `aroma.demo` y `plomeria.demo`; la contraseña es `Demo12345*`. `bin/rails db:reset` los regenera.

### Variables de entorno

| Variable | Para qué |
|---|---|
| `SECRET_KEY_BASE` | Firma de los JWT |
| `DATABASE_USERNAME`, `DATABASE_PASSWORD`, `DATABASE_URL` | Base de datos (en producción, `DATABASE_URL`) |
| `FRONTEND_URL`, `FRONTEND_URL_UI` | Orígenes permitidos por CORS |
| `SUPER_ADMIN_PASSWORD` | Contraseña del super admin; obligatoria en producción |
| `RESEND_API_KEY`, `RESEND_FROM_EMAIL` | Correo transaccional |
| `STRIPE_API_KEY`, `STRIPE_WEBHOOK_SECRET` | Cobro |
| `REGISTRATION_RATE_LIMIT` | Tope de registros por hora y por IP (5 por defecto); solo se sube en el CI de pruebas e2e |

## Pruebas y lint

```bash
bin/rails test        # modelos, servicios, controladores; usa fixtures
bin/rubocop           # estilo Rails Omakase
bin/brakeman --no-pager
```

Los terceros (Stripe, Resend, WhatsApp) se simulan con `stub` de Minitest. En el CI, el job `e2e` descarga `draxuvo-ui` y corre las pruebas de recorrido de Playwright contra esta API.

## Despliegue

Imagen Docker (`Dockerfile`) en Render (`render.yaml`, comprobación de salud en `/up`); también se puede orquestar con Kamal.

## Más información

[`CLAUDE.md`](CLAUDE.md) describe la arquitectura, el modelo de datos y los patrones del código.
