# Despliegue y operación en producción

Runbook de la API de Draxuvo. Spec: `specs/012-deploy-produccion/` del workspace (inventario de variables en
`contracts/env-inventory.md`, listas de verificación en `quickstart.md`). Stripe: [stripe.md](stripe.md).

## Qué corre y dónde

| Pieza | Dónde | Dato clave |
|---|---|---|
| API (este repo) | Render, workspace **Draxuvo**, servicio `draxuvo-api` (`srv-db96bftg1s2s739tfi30`) | Docker, Virginia, plan `0.5c-512mb`, `https://api.draxuvo.com`, health check `/up` |
| Base de datos | Render, `draxuvo-db` (`dpg-db95kh5g1s2s73b3nutg-a`) | Postgres 17, plan `0.1c-256mb`, 1 GB, **solo red privada** (sin acceso externo) |
| Archivos subidos | Cloudflare R2, bucket privado `draxuvo-uploads` | `ACTIVE_STORAGE_SERVICE=r2`; la API entrega URLs firmadas |
| DNS | Cloudflare, zona `draxuvo.com` | `api` → CNAME a `draxuvo-api.onrender.com`, **sin proxy** |
| Correo | Resend, dominio `draxuvo.com` | remitente `Draxuvo <no-reply@draxuvo.com>` |
| Cobros | Stripe, modo prueba al lanzar | webhook → `https://api.draxuvo.com/api/v1/stripe/webhooks` |

Las variables viven en Render (Environment del servicio). Nunca en el repo. Si falta alguna obligatoria, la API no
arranca y el log dice cuáles (`RequiredEnv::MissingError`, `config/initializers/required_env.rb`).

## Desplegar

- **Automático (FR-002):** el job `deploy` de `.github/workflows/ci.yml` corre solo en un push a `main`, **después** de
  `scan_ruby`, `scan_js`, `lint`, `test` y `e2e`, y llama al **Deploy Hook** del servicio con `ref` igual al commit que
  acaba de pasar el CI. El secreto del repo es `RENDER_DEPLOY_HOOK_URL` (Render → `draxuvo-api` → Settings → Deploy Hook).
  Render no está conectado a la app de GitHub (el repo es público y el servicio se creó con su URL), por eso no se usa
  *After CI checks pass*. **Auto-Deploy del servicio debe estar en Off** para no desplegar dos veces.
- **Manual:** Render → `draxuvo-api` → **Manual Deploy → Deploy latest commit**.
- Cada cambio de variables de entorno dispara un despliegue. Al cambiar varias, hazlo en un solo guardado.
- Al arrancar, `bin/docker-entrypoint` corre `db:prepare`: aplica migraciones y, en una base vacía, los seeds (crea al
  super admin con `SUPER_ADMIN_PASSWORD`). Los datos demo **no** se cargan en producción.

## Revertir (objetivo: menos de 15 minutos)

**Código.** Render → `draxuvo-api` → **Events** (o *Deploys*) → el despliegue anterior en verde → **Rollback**. Es inmediato
porque reutiliza la imagen ya construida. Comprueba después `https://api.draxuvo.com/up`.

**Migraciones.** Revertir código no revierte la base. Antes de desplegar una migración destructiva (borrar o renombrar
columnas, cambiar tipos):
1. Crea un respaldo manual: Render → `draxuvo-db` → **Backups** → crear respaldo lógico (anota la hora).
2. Despliega. Si algo falla, haz rollback del código; si la migración ya cambió datos, restaura (siguiente sección).

## Respaldo y restauración (FR-011)

Render respalda las bases de pago por su cuenta: recuperación a un punto en el tiempo según el plan del workspace
(Hobby: últimos 3 días; Pro: 7) y respaldos lógicos retenidos 7 días (documentación de Render, octubre de 2026). Se consulta en Render → `draxuvo-db` → **Recovery** y **Backups**.

**Restaurar sin tocar producción** (así se prueba):
1. Render → `draxuvo-db` → **Recovery** → restaurar al punto elegido **a una base nueva** (`draxuvo-db-restaurada`). Genera
   un costo mientras exista.
2. Compara contra producción con la URL interna de la base nueva: conteos de `users`, `companies`, `work_orders`,
   `subscriptions` y `schema_migrations`.
3. Si es solo una prueba: borra `draxuvo-db-restaurada`.
4. Si hay que recuperar de verdad: en `draxuvo-api` cambia `DATABASE_URL` por la URL interna de la base restaurada y
   guarda (dispara un despliegue). Conserva la base anterior hasta confirmar.

Registra en `specs/012-deploy-produccion/quickstart.md` (puntos 2.14 y 2.15) la fecha de la prueba y los conteos.

## Rotar secretos

| Secreto | Cómo rotarlo | Efecto |
|---|---|---|
| `SECRET_KEY_BASE` | Nuevo valor (`openssl rand -hex 64`) en Render | Cierra **todas** las sesiones (firma los JWT) |
| `SUPER_ADMIN_PASSWORD` | Ver abajo | Solo la lee el seed al **crear** el usuario; cambiar la variable no cambia la contraseña existente |
| `STRIPE_API_KEY` | Panel de Stripe → API keys → **Roll key** (clave restringida); actualizar en Render | Sin cortes si se usa el periodo de gracia de Stripe |
| `STRIPE_WEBHOOK_SECRET` | Panel de Stripe → webhook → **Roll secret**; actualizar en Render | Hasta actualizarlo, los webhooks se rechazan con 400 |
| `RESEND_API_KEY` | Resend → API Keys → crear nueva, actualizar en Render, borrar la anterior | |
| `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` | R2 → Manage API tokens → crear nuevo, actualizar en Render, borrar el anterior | Las URLs firmadas ya emitidas dejan de funcionar |
| Contraseña de `draxuvo-db` | Render → `draxuvo-db` → rotar credenciales; actualizar `DATABASE_URL` | |

**Cambiar la contraseña del super admin** (el seed usa `find_or_create_by!`, no actualiza). Con la shell de Render
(`draxuvo-api` → **Shell**):

```bash
bin/rails runner 'u = User.find_by!(email: "draxuvo@mailinator.com"); u.update!(password: ENV.fetch("SUPER_ADMIN_PASSWORD"), password_confirmation: ENV.fetch("SUPER_ADMIN_PASSWORD"))'
```

La contraseña inicial salió de un generador aleatorio de 28 caracteres, no de las que están en el historial de git.

## Logs y errores (FR-016)

- **API:** Render → `draxuvo-api` → **Logs** (filtra por `error`). También con el MCP de Render (`list_logs`).
- **web y ui:** Cloudflare → Workers → `draxuvo-web` / `draxuvo-ui` → **Observability** (activada en la config).
- **Webhooks de Stripe:** panel de Stripe → Developers → Webhooks → el endpoint → entregas y reintentos.

## WhatsApp

Desactivado en el lanzamiento (FR-009): las variables `WHATSAPP_*` no están definidas a propósito. Enviar un ticket por
WhatsApp responde 422 con "El envío por WhatsApp no está disponible por ahora." Ningún cliente usa la verificación por OTP
y el registro de empresas no depende de ella. Para activarlo después: definir `WHATSAPP_ACCESS_TOKEN` y
`WHATSAPP_PHONE_NUMBER_ID` (y, si aplica, `WHATSAPP_OTP_TEMPLATE_NAME` / `WHATSAPP_OTP_TEMPLATE_LANG`) en Render.

## Versión mínima de la app móvil (FR-015)

`MIN_APP_VERSION_IOS` y `MIN_APP_VERSION_ANDROID` en Render (semver). Subirlas obliga a actualizar sin publicar otra
build. `GET /api/v1/app_config` devuelve los valores vigentes.

## Verificación después de cada despliegue

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://api.draxuvo.com/up          # 200
curl -s https://api.draxuvo.com/api/v1/app_config                              # JSON con las versiones mínimas
curl -si -X OPTIONS https://api.draxuvo.com/api/v1/auth/login \
  -H 'Origin: https://app.draxuvo.com' -H 'Access-Control-Request-Method: POST' | grep -i allow-origin
```

La lista completa, con resultados esperados, está en `specs/012-deploy-produccion/quickstart.md`.
