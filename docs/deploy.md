# Despliegue y operación en producción

Runbook de la API de Draxuvo. Spec: `specs/012-deploy-produccion/` del workspace (inventario de variables en
`contracts/env-inventory.md`, listas de verificación en `quickstart.md`). Stripe: [stripe.md](stripe.md).

## Qué corre y dónde

| Pieza | Dónde | Dato clave |
|---|---|---|
| API (este repo) | Render, workspace **Draxuvo**, servicio `draxuvo-api` (`srv-db96bftg1s2s739tfi30`) | Docker, Virginia, plan `0.5c-512mb` (estuvo en `1c-2g` del 2026-11-16 al 2026-11-19, spec 064), `https://api.draxuvo.com`, health check `/up` |
| Trabajos en segundo plano | Render, Background Worker `draxuvo-jobs` (spec 064) | Misma imagen, comando `/rails/bin/docker-entrypoint ./bin/jobs` (activa jemalloc), Solid Queue en modo `async` (un proceso), plan `0.5c-512mb`, sin HTTP |
| Base de datos | Render, `draxuvo-db` (`dpg-db95kh5g1s2s73b3nutg-a`) | Postgres 17, plan `0.1c-256mb`, 1 GB, **solo red privada** (sin acceso externo) |
| Archivos subidos | Cloudflare R2, bucket privado `draxuvo-uploads` | `ACTIVE_STORAGE_SERVICE=r2`; la API entrega URLs firmadas |
| DNS | Cloudflare, zona `draxuvo.com` | `api` → CNAME a `draxuvo-api.onrender.com`, **sin proxy** |
| Correo | Resend, dominio `draxuvo.com` | remitente `Draxuvo <no-reply@draxuvo.com>` |
| Cobros | Stripe, modo prueba al lanzar | webhook → `https://api.draxuvo.com/api/v1/stripe/webhooks` |

Las variables viven en Render, nunca en el repo, y la **API es la única fuente**: se cambian en `draxuvo-api` → Environment.
El worker copia de ahí las que comparte (`fromService` en `render.yaml`) y solo define las suyas (`SOLID_QUEUE_SUPERVISOR_MODE=async`,
`RAILS_MAX_THREADS=10`). La copia se refresca **en cada sync del Blueprint**, no al cambiar la variable: después de cambiar una
compartida en la API, sincroniza el Blueprint (abajo) y despliega el worker. Si agregas a la API una variable que un trabajo usa,
agrégala también al worker en `render.yaml`. Lista y motivos: `specs/064-separar-solid-queue/contracts/render-services.md` del
workspace. Si falta alguna obligatoria, la API no
arranca y el log dice cuáles (`RequiredEnv::MissingError`, `config/initializers/required_env.rb`).

## Desplegar

- **Automático (FR-002):** el job `deploy` de `.github/workflows/ci.yml` corre solo en un push a `main`, **después** de
  `scan_ruby`, `scan_js`, `lint`, `test` y `e2e`, y llama a los **Deploy Hooks** de la API y luego del worker, los dos con
  `ref` igual al commit que acaba de pasar el CI: nunca corren código distinto. Secretos del repo: `RENDER_DEPLOY_HOOK_URL`
  (Render → `draxuvo-api` → Settings → Deploy Hook) y `RENDER_WORKER_DEPLOY_HOOK_URL` (Render → `draxuvo-jobs` → Settings →
  Deploy Hook). Si falta cualquiera, el job falla sin llamar a ninguno; si el primero responde y el segundo falla, el job
  queda en rojo: relánzalo (vuelve a pedir los dos al mismo commit). Render no está conectado a la app de GitHub (el repo es
  público y los servicios se crearon con su URL), por eso no se usa *After CI checks pass*. **Auto-Deploy de los dos
  servicios debe estar en Off** para no desplegar dos veces.
- **Manual:** Render → servicio → **Manual Deploy → Deploy latest commit**. Despliega **los dos** (API y `draxuvo-jobs`) al
  mismo commit.
- Cada cambio de variables de entorno dispara un despliegue. Al cambiar varias, hazlo en un solo guardado.
- Al arrancar, `bin/docker-entrypoint` corre `db:prepare`: aplica migraciones y, en una base vacía, los seeds (crea al
  super admin con `SUPER_ADMIN_PASSWORD`). Los datos demo **no** se cargan en producción. Las unidades de medida (`units`, 9 filas) son datos de referencia: se
  reponen solas al migrar (`SeedUnits`), en el arranque (`Unit.ensure_catalog!`) y al dar de alta una empresa. Si vacías
  la base, verifica con `bin/rails runner 'puts Unit.count'` (debe dar 9); sin ellas fallaban las demos y el alta de empresas.
- **El worker no migra.** Al arrancar, `bin/jobs` espera a que no queden migraciones pendientes (pregunta cada 5 s; tope
  `MIGRATION_WAIT_SECONDS`, 600 por omisión) y solo entonces arranca Solid Queue. Si vence el tope sale con error y Render lo
  reinicia, que vuelve a esperar. A mano: `bin/rails db:wait_for_migrations`.
- **Apagado.** Al desplegar, Render manda SIGTERM al worker y espera 120 s (`maxShutdownDelaySeconds`); Solid Queue deja
  terminar los trabajos en curso hasta 100 s (`config.solid_queue.shutdown_timeout`) y regresa a la cola los demás.

## Revertir (objetivo: menos de 15 minutos)

**Código.** Render → `draxuvo-api` → **Events** (o *Deploys*) → el despliegue anterior en verde → **Rollback**. Es inmediato
porque reutiliza la imagen ya construida. **Haz lo mismo en `draxuvo-jobs`, al mismo commit.** Comprueba después
`https://api.draxuvo.com/up` y que el log del worker diga `Started Supervisor(async)`.

**El worker falla y la cola se detiene.** Vuelta de emergencia: en `draxuvo-api` pon `SOLID_QUEUE_IN_PUMA=true` (Solid Queue
vuelve a correr dentro de Puma, `config/puma.rb`; solo `true` o `1` lo activan). Solo con la API en `1c-2g`: en 512 MB así se caía por memoria. Mientras tanto,
detén `draxuvo-jobs` (Suspend) o no habrá dos programadores de recurrentes, aunque Solid Queue no duplica una misma corrida.

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
| `MERCADO_PAGO_CLIENT_SECRET` / `MERCADO_PAGO_WEBHOOK_SECRET` | Mercado Pago Developers → la aplicación → renovar; actualizar en Render y sincronizar el Blueprint | Solo con OAuth. Hasta actualizar la clave de avisos, los avisos se rechazan y los cobros se resuelven con el barrido |
| Contraseña de `draxuvo-db` | Render → `draxuvo-db` → rotar credenciales; actualizar `DATABASE_URL` | |

**Cambiar la contraseña del super admin** (el seed usa `find_or_create_by!`, no actualiza). Con la shell de Render
(`draxuvo-api` → **Shell**):

```bash
bin/rails runner 'u = User.find_by!(email: "draxuvo@mailinator.com"); u.update!(password: ENV.fetch("SUPER_ADMIN_PASSWORD"), password_confirmation: ENV.fetch("SUPER_ADMIN_PASSWORD"))'
```

La contraseña inicial salió de un generador aleatorio de 28 caracteres, no de las que están en el historial de git.

## Logs y errores (FR-016)

- **Monitoreo externo (spec 071):** avisos de caída, latido del worker, errores (Sentry) y logs con búsqueda y alertas
  (Better Stack). Cuentas, variables y qué hacer ante cada aviso: [monitoreo.md](monitoreo.md).
- **API:** Render → `draxuvo-api` → **Logs** (filtra por `error`). También con el MCP de Render (`list_logs`). En
  producción cada petición es una línea JSON (`{"method":…,"request_id":…}`); búscala por su `request_id` (el encabezado
  `X-Request-Id` de la respuesta).
- **Trabajos:** Render → `draxuvo-jobs` → **Logs**. Señales al arrancar: `[jobs] jemalloc activo` (si dice `inactivo`, el
  comando del worker no pasa por `/rails/bin/docker-entrypoint`: el Docker Command de Render reemplaza el `ENTRYPOINT` de la imagen), `[migration_wait] base al día` (o
  `esperando migraciones…`), `SolidQueue-1.4.x Started Supervisor(async)`, y después cada trabajo con `Performing` / `Performed`.
  Si faltan variables, no arranca y el log dice `RequiredEnv::MissingError`.
- **Misma llave en los dos:** la API y el worker escriben al arrancar `[boot] secret_key_base sha256:<8 hex>`; deben coincidir.
  Si no, el worker tiene una copia vieja de `SECRET_KEY_BASE` (sesiones inválidas y la llave de WhatsApp ilegible): sincroniza
  el Blueprint y despliega el worker.
- **Memoria:** MCP de Render, `get_metrics` con `memory_usage` de cada servicio; `list_events` muestra `server_failed`
  (`oomKilled`) si alguno se queda sin memoria.
- **web y ui:** Cloudflare → Workers → `draxuvo-web` / `draxuvo-ui` → **Observability** (activada en la config).
- **Webhooks de Stripe:** panel de Stripe → Developers → Webhooks → el endpoint → entregas y reintentos.

## WhatsApp

Desde la spec 047 **WhatsApp se configura desde el panel**, sin tocar variables de entorno en Render: el super admin entra a
`/whatsapp` y ahí conecta la cuenta, elige y verifica las plantillas, enciende los interruptores, manda un mensaje de
prueba y ve el historial. Mientras no se conecte, el canal queda como no disponible: enviar un ticket responde 422 con
"El envío por WhatsApp no está disponible por ahora.", y el correo y las alertas del panel siguen funcionando.

**Cómo conectarlo (una vez):**

1. En Meta crea una **llave de acceso** de preferencia de *usuario del sistema* (no vence) con los permisos
   `whatsapp_business_messaging` y `whatsapp_business_management`, y anota el **identificador del número** (Phone number ID)
   y el **identificador de la cuenta** (WhatsApp Business Account ID).
2. En `/whatsapp` → «Conectar» captura los tres datos. Draxuvo los verifica con Meta **antes** de guardarlos; si Meta los
   rechaza no se guarda nada y la pantalla dice el motivo.
3. Crea las plantillas en Meta (WhatsApp Manager → Message templates) con los datos exactos de «Cómo crearla en Meta»
   (`/whatsapp` → guía): nombre, idioma, categoría *Utility* y texto con sus variables. Draxuvo **solo lee y verifica**
   plantillas, no las crea. Solo el **código de verificación** usa plantilla (1 variable: el código de 6 dígitos); el ticket
   se manda como documento o texto y no necesita plantilla.
4. Espera la aprobación, pulsa «Verificar ahora» en el código de verificación y enciende primero el interruptor del tipo y
   luego el general. Se recomienda probar antes con «Enviar prueba» (también la del ticket, que solo necesita la conexión).

**Cuentas de prueba de Meta.** Meta no deja listar los números ni las plantillas de una cuenta de prueba (error 100 con
subcódigo 2388339): Draxuvo acepta la conexión con un aviso, las plantillas quedan «Sin verificar» y solo se puede probar el
ticket. Para el código de verificación hace falta una cuenta real con número y plantilla aprobada.

**Las variables `WHATSAPP_*` quedan solo de respaldo.** Mientras el panel nunca se haya usado, si existen
`WHATSAPP_ACCESS_TOKEN` y `WHATSAPP_PHONE_NUMBER_ID` (y, opcionalmente, `WHATSAPP_OTP_TEMPLATE_NAME` / `_LANG`) el envío
funciona como siempre. `WHATSAPP_STOCK_TEMPLATE_NAME` / `_LANG` ya no se usan (spec 048) y se pueden borrar de Render. En cuanto se conecta desde el panel, **el panel
manda y las variables se ignoran**, incluso si después se desconecta (para no reactivar unas variables viejas sin avisar).

**Cifrado de la llave.** La llave se guarda cifrada con claves derivadas de `SECRET_KEY_BASE`. **Rotar `SECRET_KEY_BASE`
deja ilegible la llave guardada**: la conexión pasa a «Con error» (la pantalla pide volver a capturar la llave) y hay que
reemplazarla en `/whatsapp`. Nunca se muestra completa ni queda en el historial, los registros o las respuestas de la API.

**Fallos reales.** Si Meta rechaza la llave en un envío, la conexión pasa a «Con error» y se manda **un** correo a los super
admin activos (otro solo si se recupera y vuelve a fallar); si rechaza una plantilla, se apaga solo ese tipo de mensaje y hay
que volver a encenderlo a mano cuando esté aprobada. No hay revisión automática periódica: se verifica al guardar, con
«Verificar ahora» y en cada mensaje de prueba.

**Avisos de stock bajo (spec 045).** Desde la spec 048 salen **solo por correo** y como alerta del panel y de la app: ya no hay
canal de WhatsApp ni plantilla `stock_bajo` (se puede borrar en Meta). Las preferencias de WhatsApp que ya existían se ignoran y
los envíos anteriores por WhatsApp se conservan en `alert_deliveries`. Cada correo queda registrado ahí. Para revisar qué se
mandó a quién (solo lectura):

```bash
bin/withenv prod bin/rails console --sandbox
AlertDelivery.where(company_id: 1).order(id: :desc).limit(20).pluck(:created_at, :user_id, :channel, :kind, :status, :error)
```

Los avisos corren con dos trabajos recurrentes en `config/recurring.yml`: `StockAlerts::ScanJob` (cada 5 minutos) y
`StockAlerts::DailySummaryJob` (cada hora en punto; manda el resumen a las empresas cuya hora local es la configurada).

## Avisos push de la app (spec 057)

La API manda los avisos push por el servicio de push de Expo (`Push::ExpoClient`, `https://exp.host/--/api/v2/push/send`);
las credenciales de FCM (Android) y APNs (iOS) viven en EAS, no en Render.

| Variable | Uso |
|---|---|
| `EXPO_ACCESS_TOKEN` | Opcional. Token de acceso de Expo; con «Enhanced push security» activado en el proyecto de Expo, solo quien lo tenga puede mandar a nuestros teléfonos. |
| `PUSH_ENABLED` | Opcional (por omisión `true`). `false` apaga todo envío; los teléfonos se siguen registrando. |

Trabajos recurrentes (`config/recurring.yml`): `Push::AlertsScanJob` (cada minuto, alertas operativas), `Push::ReceiptsJob`
(cada 15 minutos: recibos de Expo; `DeviceNotRegistered` desactiva el teléfono) y `Push::PruneDevicesJob` (diario a las 4:
desactiva teléfonos con 30 días sin uso y borra la bitácora `push_deliveries` de más de 90 días). «Comanda lista» y «orden
asignada» se encolan al momento (`Push::CheckReadyJob`, `Push::WorkOrderAssignedJob`); el stock bajo sale con
`StockAlerts::Dispatch`. Para revisar un envío: `PushDelivery.order(:id).last(20)` en la consola (nunca guarda el token).

## Menú QR de las mesas (spec 059)

Cada mesa tiene un enlace público `https://draxuvo.com/m/<token>` que se imprime como QR en las tarjetas
(`POST /api/v1/restaurant/menu_cards/pdf`). El comensal lo abre en `web`, que pide el menú directo a
`GET /api/v1/public/menus/:token` desde su teléfono (sin sesión).

| Variable | Uso |
|---|---|
| `PUBLIC_SITE_URL` | Base del sitio público que va en el QR y único origen CORS de `/api/v1/public/*`. En producción `https://draxuvo.com` (en `render.yaml`; sin la variable, la API usa ese mismo valor en producción). |
| `PUBLIC_MENU_RATE_LIMIT` | Opcional (por omisión `120`). Peticiones por minuto por IP al menú público; las de más responden 429. |

El enlace queda impreso: si cambia el dominio de `web`, el dominio viejo debe redirigir `/m/*` al nuevo o hay que
reimprimir las tarjetas. Regenerar el enlace de una mesa (desde el panel) invalida solo las tarjetas de esa mesa.

## Terminal integrada con Mercado Pago (spec 069)

Un negocio con el módulo `terminals` liga su Mercado Pago Point a Draxuvo para que el cobro con tarjeta se registre solo al
aprobarse en la terminal. Contratos: `specs/069-terminal-integrada/contracts/api.md` del workspace; guía de prueba:
`quickstart.md` de la misma spec.

**Credenciales propias (la forma usual, sin configurar nada en Render).** El dueño o administrador entra a Terminales →
«Conectar con mis credenciales» y la pantalla lo guía:

1. En [Mercado Pago Developers](https://www.mercadopago.com.mx/developers/panel/app) crea su aplicación (pagos presenciales,
   Point) y copia el **Access Token de producción** (`APP_USR-…`). Draxuvo lo comprueba con `GET /users/me` y
   `GET /terminals/v1/list` antes de guardarlo; si Mercado Pago lo rechaza o la aplicación no puede usar Point, no se guarda.
2. En la aplicación → **Webhooks** pega la URL que le da Draxuvo,
   `https://api.draxuvo.com/api/v1/webhooks/mercado_pago/<webhook_token>` (única por conexión; se conserva al desconectar y
   volver a conectar), con el evento **Order (Mercado Pago)**, y pega en Draxuvo la **clave secreta** que muestra Mercado Pago.
   Sin la clave los avisos se rechazan con 400, pero los cobros se resuelven igual con el barrido de cada minuto (más lento).

Este token no se renueva: si el negocio lo cambia en Mercado Pago, la conexión pasa a «Con error» y hay que capturarlo de nuevo.

**OAuth con la aplicación de Draxuvo (opcional).** Solo si la plataforma crea su propia aplicación en Mercado Pago; sin
`MERCADO_PAGO_CLIENT_ID` el panel no ofrece «Conectar Mercado Pago» y todo lo demás funciona con credenciales propias.

| Variable | Uso |
|---|---|
| `MERCADO_PAGO_CLIENT_ID` / `MERCADO_PAGO_CLIENT_SECRET` | Credenciales de la aplicación de Draxuvo (OAuth con PKCE y `offline_access`). Las usan la API y el worker (renovación): `render.yaml` las copia al worker con `fromService`, así que después de definirlas en la API sincroniza el Blueprint. |
| `MERCADO_PAGO_WEBHOOK_SECRET` | Clave secreta de Webhooks de esa aplicación; firma de `POST /api/v1/webhooks/mercado_pago`. Solo la usa la API. |
| `MERCADO_PAGO_PLATFORM_ID` / `MERCADO_PAGO_INTEGRATOR_ID` | Opcionales, los asigna Mercado Pago (`integration_data` de cada orden). Si se definen, agrégalas también al worker en `render.yaml`. |

En la aplicación de Mercado Pago: URL de redireccionamiento `https://app.draxuvo.com/terminales/mercado-pago` (`FRONTEND_URL`
+ `/terminales/mercado-pago`) y Webhooks a `https://api.draxuvo.com/api/v1/webhooks/mercado_pago` con los eventos **Order
(Mercado Pago)** y **Vinculación de aplicaciones** (desvincular la aplicación desde Mercado Pago desconecta la cuenta).

**Trabajos** (`config/recurring.yml`, en `draxuvo-jobs`): `TerminalCharges::SweepJob` cada minuto (resuelve las solicitudes
cuyo aviso no llegó, vence las que pasaron de `expires_at` y vigila las abandonadas por si se aprueban tarde) y
`TerminalConnections::RefreshJob` a las 3 a. m. (renueva los tokens de OAuth a los que les quedan menos de 30 días; las
credenciales propias se saltan). Un token rechazado deja la conexión en `error` y manda **un** correo a dueño y
administradores (`ResendMailer.terminal_connection_problem`).

**Secretos.** Los tokens y la clave de los avisos van cifrados con Active Record Encryption, con llaves derivadas de
`SECRET_KEY_BASE` (`config/initializers/active_record_encryption.rb`). **Rotar `SECRET_KEY_BASE` deja ilegibles los tokens
guardados**: cada conexión pasa a «Con error» en su siguiente uso y el negocio debe volver a conectar. Nunca salen en
respuestas, registros ni en `terminal_events`.

**Revisar un cobro** (solo lectura):

```bash
bin/withenv prod bin/rails console --sandbox
TerminalCharge.where(company_id: 1).order(id: :desc).limit(10).pluck(:id, :status, :status_detail, :amount, :provider_reference, :created_at)
TerminalEvent.where(company_id: 1).order(id: :desc).limit(20).pluck(:created_at, :kind, :data)
```

Si un pago se aprobó en la terminal pero el cobro ya se había registrado a mano, queda en «Pagos sin aplicar» (Terminales):
desde ahí el dueño lo reembolsa o lo marca como atendido.

**Sin probar con cuenta real.** Nada de esto se ha probado contra Mercado Pago real (tareas T080 y T081 de la spec): la firma
de los avisos, los montos mínimo y máximo y los modelos de Point que se pueden ligar salen de la documentación pública.

## Trabajos en segundo plano (spec 064)

Hasta la spec 064 Solid Queue corría dentro de Puma (`SOLID_QUEUE_IN_PUMA`) con 4 procesos: la API pasó de ~210 MB a ~600 MB,
Render la mató 10 veces por memoria en 512 MB y el 2026-11-16 se subió a `1c-2g`. Ahora la cola corre en el worker
`draxuvo-jobs` en modo `async` (supervisor, despachador, programador y trabajadores como hilos de un solo proceso; ~160 MB medidos
con la imagen de producción) y la API sola usa ~160 MB.

Corte en producción, en este orden; cada paso solo si el anterior se verificó (detalle y verificaciones en
`specs/064-separar-solid-queue/quickstart.md` del workspace):

1. **Antes de fusionar:** crear el worker con el Blueprint `draxuvo-api` (`exs-dbvjmpt9fdbs73bf44cg`, hecho el 2026-11-19 con el MCP
   de Render) y copiar su Deploy Hook al secreto `RENDER_WORKER_DEPLOY_HOOK_URL` del repo (solo desde el dashboard: el MCP no
   lo expone). Mientras tanto la API sigue procesando también: Solid Queue reparte los trabajos sin duplicarlos.
2. **Fusionar el PR.** El CI despliega los dos al mismo commit.
3. **`SOLID_QUEUE_IN_PUMA=false` en `draxuvo-api`** (con el MCP basta: solo `true` o `1` lo activan) y desplegar la API. Desde aquí
   solo el worker procesa.
4. **Medir 24 h** la memoria y los eventos de los dos.
5. **Bajar `draxuvo-api` a `0.5c-512mb`** (`plan` en `render.yaml` y sync del Blueprint; hecho el 2026-11-19) y medir 48 h: sin `server_failed` y memoria máxima ≤ 435 MB en cada uno.

### Blueprint

`render.yaml` es el Blueprint `draxuvo-api` (`exs-dbvjmpt9fdbs73bf44cg`) **sin sincronización automática**: un cambio en el
archivo no se aplica solo. Para aplicarlo: «plan» del Blueprint (dashboard o `plan_blueprint` del MCP), revisar el plan y
«approve». La sync conserva las variables de la API que no aparecen en el archivo (no las borra); el Blueprint lee la rama
`main`. Un cambio de `plan` también se aplica así.

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
