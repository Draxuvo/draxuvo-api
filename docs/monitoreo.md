# Monitoreo externo (spec 071)

Cómo se entera Draxuvo, sin que un cliente avise, de caídas, errores y patrones en los logs. Todo usa capas gratuitas y
se enciende con variables de entorno: sin ellas el código no reporta ni manda latidos, y nada falla (desarrollo, CI,
pruebas).

| Qué | Herramienta | Cubre |
|---|---|---|
| ¿Está arriba? | Better Stack Uptime | API (`/up`), panel, sitio; latido del worker `draxuvo-jobs` |
| Errores | Sentry | API, trabajos en segundo plano, panel, sitio y app |
| Logs | Better Stack Logs (Log Stream de Render) | API y worker, con búsqueda y alertas |
| Caídas por memoria y despliegues fallidos | Notificaciones de Render | API y worker |

Validación de punta a punta: `specs/071-monitoreo-externo/quickstart.md` del workspace.

## Límites gratuitos

Revisarlos al crear las cuentas y anotar aquí la fecha; cambian seguido.

| Herramienta | Límite (según su página de precios, 2026-11-20) | Confirmado en la cuenta |
|---|---|---|
| Sentry Developer | 1 usuario, ~5,000 errores al mes, retención corta | pendiente |
| Better Stack Uptime | 10 monitores y latidos, 1 página de estado, correo | pendiente |
| Better Stack Logs | 3 GB, 3 días de retención | pendiente (¿alertas sobre logs en la capa gratuita?) |
| Better Stack Errors | 100,000 excepciones al mes (acepta los SDK de Sentry) | plan B, no se usa |

Si la cuota de Sentry no alcanza: bajar el ruido (ver «Apagar o bajar el volumen») o cambiar los DSN por los de Better
Stack Errors, que recibe los mismos SDK sin tocar código.

## Cuentas

- **Sentry**: una organización con 4 proyectos: `draxuvo-api` (Ruby on Rails), `draxuvo-ui` y `draxuvo-web` (Next.js),
  `draxuvo-app` (React Native). Alerta de cada proyecto: «issue nuevo» por correo al responsable.
- **Better Stack**: Uptime y Logs en la misma cuenta; avisos por correo (y opcionalmente la app móvil de Better Stack).
- **Render**: Workspace → Notifications → correo en fallas de servicio y de despliegue.

## Variables

| Variable | Dónde | Para qué |
|---|---|---|
| `SENTRY_DSN` | Render, Environment de `draxuvo-api` (el worker la copia con `fromService`) | Errores de la API y de los trabajos |
| `SENTRY_ENVIRONMENT` | igual | `production` |
| `SENTRY_TRACES_SAMPLE_RATE` | opcional | `0` por omisión (sin tracing: cuida los 512 MB) |
| `HEARTBEAT_URL` | Render, Environment de `draxuvo-api` (el worker la copia) | URL del latido de Better Stack. **Secreta**: quien la conoce mantiene vivo el monitor |
| `RENDER_GIT_COMMIT` | la pone Render | `release` de los errores |
| `NEXT_PUBLIC_SENTRY_DSN` | GitHub de `ui` y `web`, variable del repo | Errores del panel y del sitio (un DSN es público por diseño) |
| `SENTRY_AUTH_TOKEN` | EAS, secreto (opcional) | Subir source maps de la app (y quitar `SENTRY_DISABLE_AUTO_UPLOAD` de `eas.json`); `ui` y `web` no suben source maps |
| `EXPO_PUBLIC_SENTRY_DSN` | EAS, ambientes `preview` y `production` | Errores de la app (llega con la siguiente compilación de EAS: el SDK es nativo) |

Tras agregar o cambiar una variable de la API: sincronizar el Blueprint `draxuvo-api` (plan → revisar → approve) y
desplegar los dos servicios ([deploy.md](deploy.md#blueprint)).

## Disponibilidad

| Monitor | Tipo | Objetivo | Frecuencia | Aviso |
|---|---|---|---|---|
| API | HTTP | `https://api.draxuvo.com/up` responde 200 | 3 min | 2 fallas seguidas (periodo de confirmación) |
| Panel | HTTP | página de entrada de `https://app.draxuvo.com` responde 200 | 3 min | igual |
| Sitio | HTTP | `https://draxuvo.com/` responde 200 | 3 min | igual |
| Trabajos en segundo plano | Latido | `HEARTBEAT_URL` recibe un `GET` | cada 5 min (gracia 5 min) | sin señal en 10 min |

El latido lo manda `Monitoring::HeartbeatJob` desde `config/recurring.yml`: lo programa el scheduler y lo ejecuta el
worker, así que su ausencia significa worker caído, atorado, sin base o esperando migraciones. Si falla la red, deja
`[Monitoring::HeartbeatJob] sin latido: <clase>` en el log (nunca la URL).

## Errores (Sentry)

- **API**: `ErrorHandler#handle_internal_error` reporta todo 500 (con `rescue_from StandardError` el middleware de Sentry no
  lo vería). Los trabajos que fallan se reportan una vez, al agotar sus reintentos. Los 4xx esperados no se reportan.
- **Panel y sitio** (`ui`, `web`): `@sentry/browser`, solo en el navegador (`src/lib/monitoring.ts`). Los errores del render
  en el servidor del Worker no van a Sentry: se ven en Cloudflare → Workers → `draxuvo-ui` / `draxuvo-web` →
  Observability. Sin source maps: las trazas salen minificadas.
- **App**: `@sentry/react-native` (errores de JavaScript y cierres nativos), etiqueta `screen` con la ruta de expo-router.
- **Contexto**: `user.id`, etiquetas `company_id`, `demo` (filtra las demos con `demo:true`) y `request_id`; `release` es
  el commit desplegado (en la app, versión y número de compilación).
- **Privacidad**: sin correo, nombre, IP, cuerpo, cookies, encabezados (salvo User-Agent), query string ni argumentos de
  trabajos (`data_collection` en `config/initializers/sentry.rb` y `lib/sentry_scrubber.rb`). Regla completa:
  `specs/071-monitoreo-externo/contracts/error-event.md`.

## Logs (Better Stack)

- En producción, cada petición de la API es una línea JSON pura (lograge, `config/initializers/lograge.rb`) con
  `method`, `path` (sin query), `controller`, `action`, `status`, `duration`, `db`, `view`, `request_id`, `user_id`,
  `company_id`, `demo` y, en un 500, `exception` (solo la clase). `GET /up` no deja línea. Las demás líneas (`[boot]`,
  `[jobs]`, `[Demo::PurgeJob]`) no cambiaron.
- **Log Stream**: Render → Workspace → Observability → Log Streams: endpoint `in.logs.betterstack.com:6514` y el token de
  la fuente «Render» de Better Stack. Aplica a la API y al worker.
- **Buscar**: por `request_id` (el encabezado `X-Request-Id` de la respuesta), `status:500`, `company_id`, `user_id`.
- **Alertas** (si la capa gratuita las permite; si no, las cubre la alerta de «issue nuevo» de Sentry):
  - más de 20 respuestas con `status` 500 en 5 minutos;
  - más de 5 líneas `Error performing` de trabajos en 15 minutos.

## En el panel (spec 073)

Dos pantallas del super admin complementan lo de arriba con datos que viven en Draxuvo:

- **Accesos** (`/accesos`): cada intento de inicio de sesión en el panel y la app, con su resultado (entró, contraseña
  incorrecta, correo sin cuenta, cuenta inactiva, bloqueado por intentos, datos inválidos), persona, empresas, IP,
  dispositivo y canal (panel, app o desconocido). Arriba, entradas y fallos de hoy y las IP y correos con más fallos de la
  última hora. Tabla `login_attempts`, de solo inserción; nunca guarda la contraseña ni el token. `LoginAttempts::PurgeJob`
  (cada día a las 4 a. m.) borra lo que pasa de **90 días**. Si guardar un intento falla, el login responde igual y la falla
  va a Sentry (`[LoginAttempts::Record] no se guardó: <clase>` en el log).
- **Estado del sistema** (`/estado`): versión desplegada y arranque de la API, latencia de la base, la cola de Solid Queue
  (última señal del worker, pendientes, en curso, fallidos de 24 h sin sus argumentos y recurrentes atrasados), los
  monitores y el latido de Better Stack y los problemas sin resolver de Sentry por proyecto. Better Stack y Sentry se
  consultan desde la API (nunca desde el navegador), en paralelo, con 5 s como máximo y una copia de 1 minuto; si fallan,
  se ve la última copia buena marcada como vieja.

Tokens de lectura (solo en la API de Render; sin ellos, esas dos tarjetas dicen «Sin configurar»):

- `BETTERSTACK_UPTIME_TOKEN`: Better Stack → Settings → API tokens → token de **Uptime** del equipo.
- `SENTRY_API_TOKEN`: Sentry → Settings → Developer Settings → Custom Integrations → **Internal Integration** con permisos
  de solo lectura: Project (Read), Issue & Event (Read) y Organization (Read). Los «Organization Auth Tokens» no sirven:
  solo tienen el alcance `org:ci` y no leen problemas.

## Qué hacer ante cada aviso

| Aviso | Primeros pasos |
|---|---|
| API caída | MCP de Render: `list_events` (¿`server_failed`, `oomKilled`?) y `get_metrics` (`memory_usage`); logs de `draxuvo-api`. Si fue un despliegue: revertir ([deploy.md](deploy.md#revertir-objetivo-menos-de-15-minutos)). |
| Panel o sitio caído | Cloudflare → Workers → `draxuvo-ui` / `draxuvo-web` → Observability y Deployments; `npx wrangler rollback --name …` |
| Latido perdido | Logs de `draxuvo-jobs`: ¿arrancó? (`SolidQueue … Started`), ¿espera migraciones (`MIGRATION_WAIT_SECONDS`)?, ¿`RequiredEnv::MissingError`?, ¿memoria? Vuelta de emergencia: `SOLID_QUEUE_IN_PUMA=true` en la API con 1c-2g (spec 064). |
| Error nuevo en Sentry | Ver `release` (¿despliegue reciente?) y `request_id`; buscar ese `request_id` en Better Stack para ver la petición y las líneas vecinas. |
| Ráfaga de 500 | Igual que «error nuevo»; si coincide con un despliegue, revertir. |

## Apagar o bajar el volumen

- **Apagar**: borrar `SENTRY_DSN` (API y worker), `NEXT_PUBLIC_SENTRY_DSN` (repos de `ui`/`web`) o `EXPO_PUBLIC_SENTRY_DSN`
  (EAS) y desplegar. Borrar `HEARTBEAT_URL` apaga el latido (y el monitor avisará: pausarlo en Better Stack antes).
- **Menos eventos**: en Sentry, «Inbound filters» (navegadores viejos, extensiones, localhost) y descartar issues ruidosos;
  en el código, `config.excluded_exceptions` (API) e `IGNORE_ERRORS` / `DENY_URLS` (`src/lib/monitoring.ts` de `ui`/`web`).
