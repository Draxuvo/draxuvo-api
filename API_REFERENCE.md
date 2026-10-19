# Draxuvo — API Reference

Base URL: `https://<tu-dominio>/api/v1`  
Protocolo: `HTTPS`  
Formato: `JSON`

---

## Índice

1. [Autenticación y Headers](#1-autenticación-y-headers)
2. [Paginación](#2-paginación)
3. [Errores](#3-errores)
4. [Auth — Login y perfil](#4-auth--login-y-perfil)
5. [Passwords](#5-passwords)
6. [Usuarios](#6-usuarios)
7. [Empresas](#7-empresas)
8. [Suscripción](#8-suscripción)
9. [Empleados](#9-empleados)
10. [Asistencias](#10-asistencias)
11. [Órdenes de trabajo](#11-órdenes-de-trabajo)
12. [Tickets](#12-tickets)
13. [Productos](#13-productos)
14. [Movimientos de stock](#14-movimientos-de-stock)
15. [Unidades](#15-unidades)
16. [Uploads (imágenes)](#16-uploads-imágenes)
17. [Dashboard](#17-dashboard)
18. [Reportes](#18-reportes)
19. [Restaurante](#19-restaurante)

---

## 1. Autenticación y Headers

Todos los endpoints (excepto los marcados como **público**) requieren los siguientes headers:

| Header | Valor | Notas |
|---|---|---|
| `Authorization` | `Bearer <jwt_token>` | Token obtenido en `/auth/login` |
| `X-Company-Id` | `<company_id>` | ID numérico de la empresa activa |
| `Content-Type` | `application/json` | Siempre en requests con body |

**El token JWT expira en 24 horas.**

### Roles disponibles

| Rol | Descripción |
|---|---|
| `staff` | Empleado básico |
| `manager` | Gerente |
| `admin` | Administrador |
| `owner` | Dueño de la empresa |
| `super_admin` | Acceso global a todas las empresas |

### Cabeceras opcionales y configuración para la app móvil (spec 011)

| Header | Dónde | Efecto |
|---|---|---|
| `locale` | Toda petición | `es` o `en`: idioma de los mensajes |
| `X-App-Version` | Toda petición de la app | Informativa (por ejemplo `1.0.0 ios`); la API no la valida |
| `Idempotency-Key` | `POST /work_orders/:id/notes` y `POST /work_orders/:id/photos` | Cadena de hasta 64 caracteres (la app manda un UUID). Sin cabecera, igual que siempre. La primera vez ejecuta y guarda estado y cuerpo de la respuesta (solo 2xx). Repetida con el mismo usuario y ruta, responde lo guardado sin crear otra nota o foto. En otra ruta responde `422`; de más de 64 caracteres, `400` |

#### `GET /app_config` — público

Sin token ni `X-Company-Id`. Responde siempre `200`:

```json
{ "min_app_version": { "ios": "1.0.0", "android": "1.0.0" } }
```

Los valores salen de `MIN_APP_VERSION_IOS` y `MIN_APP_VERSION_ANDROID`; sin definir, `0.0.0`. La app compara su versión con la de su plataforma y, si es menor, solo muestra la pantalla de actualizar.


---

## 2. Paginación

Todos los endpoints de listado aceptan:

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `limit` | integer | 20 | Elementos por página (máx. 100) |
| `page` | integer | 1 | Número de página |
| `sort` | string | varía | Columna por la que ordenar |
| `dir` | string | `desc` | Dirección: `asc` o `desc` |

### Respuesta paginada

```json
{
  "data": [...],
  "meta": {
    "current_page": 1,
    "total_pages": 5,
    "total_count": 87,
    "limit": 20
  }
}
```

---

## 3. Errores

Todas las respuestas de error siguen este formato:

```json
{
  "error": {
    "status": 422,
    "message": "Error de validación",
    "details": "El campo X no puede estar vacío"
  }
}
```

| Código HTTP | Significado |
|---|---|
| `400` | Bad Request — parámetros inválidos o faltantes |
| `401` | Unauthorized — token inválido o expirado |
| `403` | Forbidden — sin permiso para realizar la acción |
| `404` | Not Found — recurso no encontrado |
| `422` | Unprocessable Entity — validación fallida |
| `500` | Internal Server Error |

---

## 4. Auth — Login y perfil

### `POST /auth/login` — público

Iniciar sesión. Si el usuario tiene un empleado asociado, registra su checkin del día automáticamente.

**Body:**
```json
{
  "email": "usuario@empresa.com",
  "password": "mi_contraseña"
}
```

**Respuesta `200`:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiJ9...",
  "user": {
    "id": 1,
    "first_name": "Juan",
    "middle_name": null,
    "last_name": "Pérez",
    "second_last_name": "López",
    "email": "juan@empresa.com",
    "phone": "5512345678",
    "role": "admin",
    "active": true,
    "created_at": "2026-01-15T10:00:00Z",
    "updated_at": "2026-04-20T08:30:00Z",
    "companies": [
      { "id": 1, "name": "Mi Empresa" }
    ]
  }
}
```

---

### `GET /auth/me`

Devuelve el perfil del usuario autenticado.

**Respuesta `200`:**
```json
{
  "user": { /* mismo objeto que en login */ }
}
```

---

## 5. Passwords

### `PUT /passwords/update`

Cambiar contraseña del usuario autenticado.

**Body:**
```json
{
  "current_password": "contraseña_actual",
  "new_password": "nueva_contraseña",
  "new_password_confirmation": "nueva_contraseña"
}
```

**Respuesta `200`:**
```json
{
  "message": "Contraseña actualizada exitosamente",
  "user": { /* objeto usuario */ }
}
```

---

### `POST /passwords/reset` — público

Solicitar correo de restablecimiento de contraseña.

**Body:**
```json
{
  "email": "usuario@empresa.com"
}
```

**Respuesta `200`:**
```json
{
  "message": "Se ha enviado un correo con las instrucciones para restablecer tu contraseña"
}
```

---

### `PUT /passwords/update_with_token` — público

Establecer nueva contraseña usando el token del correo de restablecimiento.

**Body:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiJ9...",
  "new_password": "nueva_contraseña",
  "new_password_confirmation": "nueva_contraseña"
}
```

**Reglas:**
- Mínimo 6 caracteres
- `new_password` y `new_password_confirmation` deben coincidir
- Activa el usuario (`active: true`) y al empleado asociado si existe

**Respuesta `200`:**
```json
{
  "message": "Contraseña restablecida exitosamente",
  "user": { /* objeto usuario */ }
}
```

---

## 6. Usuarios

### `GET /users`

Lista usuarios de la empresa. Excluye empleados con cuenta asociada y emails del sistema.

**Query params:**

| Parámetro | Tipo | Descripción |
|---|---|---|
| `search` | string | Busca en nombre y email |
| `email` | string | Filtrar por email exacto |
| `role` | string | `staff`, `manager`, `admin`, `owner` |
| `sort` | string | `first_name`, `email`, `role`, `created_at` |

**Respuesta `200`:** paginada con array de objetos usuario.

---

### `GET /users/:id`

**Respuesta `200`:** objeto usuario completo.

---

### `POST /users`

> Requiere rol `admin`, `owner` o `super_admin` para asignar `role`, `password` y `company_ids`.

**Body:**
```json
{
  "user": {
    "first_name": "Ana",
    "middle_name": null,
    "last_name": "García",
    "second_last_name": null,
    "email": "ana@empresa.com",
    "phone": "5598765432",
    "role": "manager",
    "active": true,
    "company_ids": [1]
  }
}
```

> Si no se envía `password`, se genera automáticamente y se envía un correo de configuración.

**Respuesta `201`:** objeto usuario.

---

### `PATCH /users/:id`

**Body:**
```json
{
  "user": {
    "first_name": "Ana",
    "last_name": "García",
    "phone": "5598765432",
    "role": "admin",
    "active": true,
    "company_ids": [1, 2]
  }
}
```

> `role`, `active` y `company_ids` solo son editables por `admin`/`owner`/`super_admin`.

**Respuesta `200`:** objeto usuario.

---

### `PATCH /users/:id/active`

Alterna el estado activo/inactivo del usuario.

**Respuesta `200`:** objeto usuario con `active` actualizado.

---

### `DELETE /users/:id`

**Respuesta `200`:**
```json
{ "message": "Usuario eliminado" }
```

---

## 7. Empresas

### `GET /company`

Devuelve la empresa actual (según `X-Company-Id`).

**Respuesta `200`:**
```json
{
  "id": 1,
  "name": "Mi Empresa SA",
  "slug": "mi-empresa-sa",
  "plan": "business",
  "stripe_id": "cus_xxxx",
  "users_count": 12,
  "created_at": "2026-01-01T00:00:00Z",
  "updated_at": "2026-04-01T00:00:00Z"
}
```

---

### `PATCH /company`

Actualizar datos de la empresa actual. Requiere `admin` u `owner`.

**Body:**
```json
{
  "company": {
    "name": "Nuevo Nombre SA",
    "plan": "enterprise"
  }
}
```

**Respuesta `200`:** objeto empresa.

---

### `GET /companies` — solo `super_admin`

Lista todas las empresas (paginado).

---

### `GET /companies/:id` — solo `super_admin`

**Respuesta `200`:** objeto empresa.

---

### `POST /companies` — solo `super_admin`

**Body:**
```json
{
  "company": {
    "name": "Nueva Empresa",
    "plan": "starter"
  }
}
```

**Planes disponibles:** `starter`, `business`, `enterprise`

**Respuesta `201`:** objeto empresa.

---

### `PATCH /companies/:id` — solo `super_admin`

**Respuesta `200`:** objeto empresa.

---

### `DELETE /companies/:id` — solo `super_admin`

**Respuesta `204`:** sin body.

---

## 8. Suscripción

> Estos endpoints no verifican el estado de la suscripción; siempre son accesibles. Requieren rol `admin` u `owner`.

### `GET /subscription`

**Respuesta `200`:**
```json
{
  "id": 5,
  "plan": "business",
  "status": "active",
  "billing_cycle": "monthly",
  "amount": 45000,
  "iva_amount": 7200,
  "total_with_iva": 52200,
  "iva_rate": 0.16,
  "trial_ends_at": null,
  "trial_days_remaining": 0,
  "current_period_start": "2026-04-01T00:00:00Z",
  "current_period_end": "2026-05-01T00:00:00Z",
  "active_access": true,
  "cancelled_at": null,
  "created_at": "2026-01-15T00:00:00Z"
}
```

> Si la empresa no tiene suscripción, devuelve `plan: "starter"` y `status: "expired"`.

**Estados posibles:** `trialing`, `active`, `past_due`, `cancelled`, `expired`

---

### `POST /subscription/checkout`

Crea una sesión de pago en Stripe para cambiar de plan.

**Body:**
```json
{
  "plan": "business",
  "success_url": "https://mi-app.com/billing/success",
  "cancel_url": "https://mi-app.com/billing/cancel"
}
```

**Planes pagos:** `business`, `enterprise`

**Respuesta `200`:**
```json
{
  "checkout_url": "https://checkout.stripe.com/pay/cs_xxx..."
}
```

Redirige al usuario a `checkout_url`.

---

### `DELETE /subscription`

Cancela la suscripción activa al final del período.

**Respuesta `200`:** objeto suscripción con `status: "cancelled"`.

---

## 9. Empleados

### `GET /employees`

**Query params:**

| Parámetro | Tipo | Descripción |
|---|---|---|
| `search` | string | Busca en nombre, posición, departamento |
| `status` | string | `active` o `inactive` |
| `sort` | string | `name`, `position`, `department`, `salary`, `created_at` |

**Respuesta `200`:** paginada con array de empleados.

```json
{
  "data": [
    {
      "id": 1,
      "name": "Carlos López",
      "email": "carlos@empresa.com",
      "phone": "5512345678",
      "position": "Técnico",
      "department": "Operaciones",
      "salary": "15000.00",
      "status": "active",
      "created_at": "2026-02-01T00:00:00Z",
      "updated_at": "2026-04-10T00:00:00Z",
      "user": {
        "id": 3,
        "email": "carlos@empresa.com",
        "role": "staff",
        "active": true
      }
    }
  ],
  "meta": { ... }
}
```

---

### `GET /employees/:id`

**Respuesta `200`:** objeto empleado completo.

---

### `POST /employees`

Crea un empleado. Si se envía `email`, crea automáticamente un usuario con rol `staff` y envía un correo de configuración de contraseña.

**Body:**
```json
{
  "employee": {
    "name": "María Torres",
    "position": "Asistente",
    "department": "Ventas",
    "salary": 12000,
    "email": "maria@empresa.com",
    "phone": "5587654321"
  }
}
```

**Respuesta `201`:** objeto empleado con usuario anidado.

---

### `PATCH /employees/:id`

**Body:**
```json
{
  "employee": {
    "position": "Coordinadora",
    "salary": 14000
  }
}
```

> No se puede cambiar `email` ni `phone` por esta ruta.

**Respuesta `200`:** objeto empleado.

---

### `DELETE /employees/:id`

Elimina el empleado y su usuario asociado (si tiene).

**Respuesta `200`:**
```json
{ "message": "Empleado eliminado" }
```

---

### `PATCH /employees/:id/active`

Alterna estado `active` ↔ `inactive`.

**Respuesta `200`:** objeto empleado con `status` actualizado.

---

### `POST /employees/:id/checkin`

Registra entrada. Falla si ya hay un checkin abierto del día.

**Body (opcional):**
```json
{
  "lat": 19.4326,
  "lng": -99.1332
}
```

**Respuesta `201`:**
```json
{
  "id": 45,
  "employee_id": 1,
  "checkin_at": "2026-04-23T08:05:00Z",
  "checkout_at": null,
  "attendance_type": "normal",
  "lat": 19.4326,
  "lng": -99.1332
}
```

---

### `POST /employees/:id/checkout`

Registra salida del checkin abierto más reciente.

**Respuesta `200`:** objeto asistencia con `checkout_at` llenado.

---

## 10. Asistencias

### `GET /attendances`

**Query params:**

| Parámetro | Tipo | Descripción |
|---|---|---|
| `search` | string | Busca en nombre del empleado |
| `employee_id` | integer | Filtrar por empleado |
| `from` | date `YYYY-MM-DD` | Desde esta fecha de checkin |
| `to` | date `YYYY-MM-DD` | Hasta esta fecha de checkin |
| `sort` | string | `checkin_at`, `checkout_at`, `created_at` |

**Respuesta `200`:** paginada con array de asistencias.

---

## 11. Órdenes de trabajo

### `GET /work_orders`

**Query params:**

| Parámetro | Tipo | Descripción |
|---|---|---|
| `search` | string | Busca en título y descripción |
| `status` | string | `pending`, `in_progress`, `in_review`, `completed`, `cancelled` |
| `priority` | string | `low`, `medium`, `high`, `urgent` |
| `employee_id` | integer | Filtrar por empleado asignado |
| `sort` | string | `title`, `priority`, `status`, `due_date`, `created_at` |

**Respuesta `200`:** paginada con array de órdenes.

```json
{
  "data": [
    {
      "id": 10,
      "title": "Instalación de sistema",
      "description": "Instalar y configurar...",
      "priority": "high",
      "priority_label": "Alta",
      "status": "in_progress",
      "status_label": "En progreso",
      "due_date": "2026-04-30",
      "completed_at": null,
      "notes": null,
      "progress": 60,
      "total": "3500.00",
      "created_at": "2026-04-15T09:00:00Z",
      "employee": {
        "id": 1,
        "name": "Carlos López"
      },
      "items_count": 5,
      "completed_items_count": 3
    }
  ]
}
```

---

### `GET /work_orders/:id`

Devuelve la orden con el array completo de items.

**Respuesta `200`:**
```json
{
  "id": 10,
  "title": "Instalación de sistema",
  "...",
  "items": [
    {
      "id": 1,
      "description": "Cable HDMI 3m",
      "quantity": 2,
      "unit": "pza",
      "unit_price": "150.00",
      "subtotal": "300.00",
      "status": "completed",
      "position": 0,
      "product_id": 5
    }
  ]
}
```

---

### `POST /work_orders`

**Body:**
```json
{
  "work_order": {
    "title": "Mantenimiento preventivo",
    "description": "Revisión mensual de equipos",
    "priority": "medium",
    "due_date": "2026-05-01",
    "notes": "Llevar herramientas básicas",
    "employee_id": 3
  },
  "items": [
    {
      "description": "Aceite lubricante",
      "quantity": 2,
      "unit": "lt",
      "unit_price": 85.00,
      "product_id": 12
    }
  ]
}
```

> `items` es opcional. Si se envía `product_id`, los campos del producto se completan automáticamente.

**Respuesta `201`:** orden con items.

---

### `PATCH /work_orders/:id`

Actualiza la orden. Si se envía `items`, reemplaza la lista (los items con `id` se actualizan, los nuevos se crean, los que falten se eliminan).

**Body:**
```json
{
  "work_order": {
    "title": "Mantenimiento preventivo (actualizado)",
    "priority": "high"
  },
  "items": [
    { "id": 1, "quantity": 3, "unit_price": 85.00 },
    { "description": "Nuevo item", "quantity": 1, "unit_price": 200.00 }
  ]
}
```

**Respuesta `200`:** orden actualizada con items.

---

### `DELETE /work_orders/:id` — requiere `admin` u `owner`

**Respuesta `200`:**
```json
{ "message": "Orden eliminada" }
```

---

### `PATCH /work_orders/:id/update_status`

Cambia el estado de una orden.

**Body:**
```json
{
  "status": "in_progress"
}
```

**Estados válidos:** `pending` → `in_progress` → `in_review` → `completed` → `cancelled`

> Al pasar a `completed`, se genera automáticamente un Ticket si no existe.

**Respuesta `200`:** objeto orden con nuevo status.

---

### `POST /work_orders/:id/items`

Agrega un item a la orden.

**Body:**
```json
{
  "description": "Conector RJ45",
  "quantity": 10,
  "unit": "pza",
  "unit_price": 12.50,
  "product_id": 8,
  "position": 2
}
```

> Si se envía `product_id`, `description`, `unit` y `unit_price` se toman del producto si no se especifican.

**Respuesta `201`:** orden completa con todos sus items.

---

### `PATCH /work_orders/:id/items/:item_id`

**Body:**
```json
{
  "description": "Conector RJ45 Cat6",
  "quantity": 15,
  "unit_price": 14.00
}
```

**Respuesta `200`:** orden con items actualizados.

---

### `DELETE /work_orders/:id/items/:item_id`

**Respuesta `200`:** orden con items restantes.

---

### `PATCH /work_orders/:id/items/:item_id/toggle`

Alterna el estado del item entre `pending` ↔ `completed`.

**Respuesta `200`:** orden con items actualizados.

---

## 12. Tickets

Los tickets se generan **automáticamente** cuando una orden pasa a `completed`. No existe un endpoint de creación manual.

### `GET /tickets`

**Query params:**

| Parámetro | Tipo | Descripción |
|---|---|---|
| `status` | string | `pending` o `paid` |
| `sort` | string | `folio`, `status`, `total`, `created_at`, `paid_at` |

**Respuesta `200`:** paginada con array de tickets.

```json
{
  "data": [
    {
      "id": 3,
      "folio": "T-000003",
      "status": "pending",
      "status_label": "Pendiente de pago",
      "total": "3500.00",
      "notes": null,
      "paid_at": null,
      "created_at": "2026-04-20T14:00:00Z",
      "work_order": {
        "id": 10,
        "title": "Instalación de sistema",
        "priority": "high",
        "status": "completed"
      }
    }
  ]
}
```

---

### `GET /tickets/:id`

Devuelve el ticket con el detalle de items.

**Respuesta `200`:**
```json
{
  "id": 3,
  "folio": "T-000003",
  "...",
  "items": [
    {
      "description": "Cable HDMI 3m",
      "quantity": 2,
      "unit": "pza",
      "unit_price": "150.00",
      "subtotal": "300.00"
    }
  ]
}
```

---

### `PATCH /tickets/:id/mark_as_paid`

Marca el ticket como pagado. Falla si ya está pagado.

**Respuesta `200`:** objeto ticket con `status: "paid"` y `paid_at` llenado.

---

### `GET /tickets/:id/download`

Descarga el PDF del ticket.

**Respuesta `200`:**
- `Content-Type: application/pdf`
- `Content-Disposition: attachment; filename="ticket-T-000003.pdf"`

---

### `POST /tickets/:id/send_whatsapp`

Genera el PDF y lo envía por WhatsApp al número indicado.

**Body:**
```json
{
  "phone": "5219876543210"
}
```

> El número debe incluir código de país sin `+`. México: `52` + 10 dígitos.

**Requiere variables de entorno:** `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`

**Respuesta `200`:**
```json
{
  "message": "Ticket enviado por WhatsApp exitosamente"
}
```

---

## 13. Productos

### `GET /products`

**Query params:**

| Parámetro | Tipo | Descripción |
|---|---|---|
| `search` | string | Busca en nombre, SKU, descripción, categoría |
| `category` | string | Filtrar por categoría exacta |
| `available` | boolean (`true`) | Solo productos disponibles |
| `low_stock` | boolean (`true`) | Solo con stock ≤ stock mínimo |
| `sort` | string | `name`, `sku`, `stock`, `min_stock`, `unit_cost`, `category`, `created_at` |

**Respuesta `200`:** paginada.

```json
{
  "data": [
    {
      "id": 5,
      "sku": "CABLE-001",
      "name": "Cable HDMI 3m",
      "description": "Cable HDMI 4K",
      "category": "Cables",
      "price": "150.00",
      "unit_cost": "80.00",
      "stock": 25,
      "min_stock": 5,
      "available": true,
      "low_stock": false
    }
  ]
}
```

---

### `GET /products/menu`

Devuelve solo productos disponibles agrupados por categoría. Ideal para seleccionar productos al crear items de orden.

**Query params:** `search`, `category`

**Respuesta `200`:**
```json
{
  "menu": [
    {
      "category": "Cables",
      "items": [
        { /* objeto producto */ }
      ]
    },
    {
      "category": "Sin categoría",
      "items": [...]
    }
  ]
}
```

---

### `GET /products/:id`

**Respuesta `200`:** objeto producto.

---

### `POST /products`

**Body:**
```json
{
  "product": {
    "sku": "CONEC-002",
    "name": "Conector RJ45 Cat6",
    "description": "Para redes gigabit",
    "category": "Conectores",
    "price": 14.00,
    "unit_cost": 6.50,
    "stock": 200,
    "min_stock": 20,
    "available": true
  }
}
```

**Respuesta `201`:** objeto producto.

---

### `PATCH /products/:id`

**Body:** mismos campos que en create (todos opcionales).

**Respuesta `200`:** objeto producto.

---

### `DELETE /products/:id`

**Respuesta `200`:**
```json
{ "message": "Producto eliminado" }
```

---

### `POST /products/import`

Importa productos masivamente desde Excel (`.xlsx`, `.xls`) o CSV.

**Body:** `multipart/form-data`

| Campo | Tipo | Descripción |
|---|---|---|
| `file` | file | Archivo Excel/CSV |

**Respuesta `200`:**
```json
{
  "message": "Importación completada",
  "created": 45,
  "updated": 12,
  "errors": ["Fila 5: SKU requerido"]
}
```

---

### `GET /products/template`

Descarga la plantilla Excel para importación.

**Respuesta `200`:**
- `Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`
- Archivo: `plantilla_productos.xlsx`

**Columnas de la plantilla:** `SKU`, `NOMBRE`, `DESCRIPCIÓN`, `CATEGORÍA`, `PRECIO`, `COSTO UNITARIO`, `STOCK`, `STOCK MÍNIMO`, `DISPONIBLE`

---

## 14. Movimientos de stock

### `GET /products/:product_id/stock_movements`

**Query params:**

| Parámetro | Tipo | Descripción |
|---|---|---|
| `search` | string | Busca en nota |
| `sort` | string | `qty`, `created_at` |

**Respuesta `200`:** paginada con movimientos del producto.

---

### `POST /products/:product_id/stock_movements`

Registra una entrada o salida de inventario.

**Body:**
```json
{
  "stock_movement": {
    "movement_type": "entry",
    "qty": 50,
    "note": "Compra a proveedor XYZ"
  }
}
```

| `movement_type` | Efecto |
|---|---|
| `entry` | Suma stock |
| `exit` | Resta stock (falla si no hay suficiente) |

**Respuesta `201`:**
```json
{
  "movement": {
    "id": 22,
    "movement_type": "entry",
    "qty": 50,
    "note": "Compra a proveedor XYZ",
    "created_at": "2026-04-23T11:00:00Z"
  },
  "product": { /* objeto producto con stock actualizado */ }
}
```

---

## 15. Unidades

### `GET /units`

Devuelve todas las unidades de medida disponibles.

**Query params:**

| Parámetro | Tipo | Descripción |
|---|---|---|
| `group` | string | Filtrar por grupo (ej. `weight`, `length`, `volume`) |

**Respuesta `200`:**
```json
[
  { "id": 1, "key": "pza", "name": "Pieza", "group": "quantity" },
  { "id": 2, "key": "kg", "name": "Kilogramo", "group": "weight" },
  { "id": 3, "key": "lt", "name": "Litro", "group": "volume" }
]
```

---

## 16. Uploads (imágenes)

> **Este controller no requiere autenticación.**

Tipos permitidos: `jpeg`, `png`, `gif`, `webp`, `svg`  
Tamaño máximo: **10 MB**

### `GET /uploads`

Lista todas las imágenes subidas.

**Respuesta `200`:**
```json
[
  {
    "id": "abc123key",
    "filename": "logo.png",
    "content_type": "image/png",
    "byte_size": 45321,
    "url": "https://tu-dominio.com/rails/active_storage/blobs/..."
  }
]
```

---

### `GET /uploads/:id`

El `:id` es la **key** del blob (string), no un número.

**Respuesta `200`:** objeto imagen.

---

### `POST /uploads`

**Body:** `multipart/form-data`

| Campo | Tipo |
|---|---|
| `file` | image file |

**Respuesta `201`:** objeto imagen con URL.

---

### `DELETE /uploads/:id`

Elimina la imagen del almacenamiento.

**Respuesta `204`:** sin body.

---

## 17. Dashboard

### `GET /dashboard`

Estadísticas generales de la empresa.

**Respuesta `200`:**
```json
{
  "employees": {
    "total": 25,
    "active": 23,
    "inactive": 2
  },
  "users": {
    "total": 18,
    "by_role": {
      "staff": 10,
      "manager": 4,
      "admin": 2,
      "owner": 1,
      "super_admin": 0
    }
  },
  "work_orders": {
    "total": 142,
    "by_status": {
      "pending": 8,
      "in_progress": 15,
      "in_review": 5,
      "completed": 110,
      "cancelled": 4
    },
    "by_priority": {
      "low": 30,
      "medium": 60,
      "high": 40,
      "urgent": 12
    }
  },
  "tickets": {
    "total": 110,
    "pending": 18,
    "paid": 92,
    "total_revenue": 425300.00,
    "pending_revenue": 54200.00
  },
  "inventory": {
    "total": 85,
    "available": 78,
    "unavailable": 7,
    "low_stock": 4,
    "out_of_stock": 2
  },
  "attendance": {
    "today": {
      "total": 20,
      "normal": 18,
      "late": 2,
      "absent": 0
    },
    "this_month": 440
  }
}
```

---

## 18. Reportes

> Todos los endpoints de reportes requieren rol `admin`, `owner` o `super_admin`.

### `GET /reports/summary`

Resumen ejecutivo del período.

**Query params:**

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `period` | string | `monthly` | `weekly`, `monthly`, `annual` |
| `date` | date `YYYY-MM-DD` | hoy | Fecha de referencia del período |

**Respuesta `200`:** métricas agregadas del período (ingresos, órdenes completadas, empleados activos, etc.).

---

### `GET /reports/income`

Reporte de ingresos (tickets pagados) agrupados en el tiempo.

**Query params:**

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `from` | date `YYYY-MM-DD` | hace 1 mes | Fecha inicio |
| `to` | date `YYYY-MM-DD` | hoy | Fecha fin |
| `group_by` | string | `month` | `week`, `month`, `year` |

**Respuesta `200`:**
```json
{
  "total": 185400.00,
  "data": [
    { "period": "2026-01", "amount": 45000.00, "count": 12 },
    { "period": "2026-02", "amount": 72000.00, "count": 18 }
  ]
}
```

---

### `GET /reports/expenses`

Reporte de gastos (costo de products usados en órdenes). Mismos params que `/reports/income`.

---

### `GET /reports/payroll`

Reporte de nómina para un rango de fechas.

**Query params:**

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `from` | date `YYYY-MM-DD` | hace 1 mes | Fecha inicio |
| `to` | date `YYYY-MM-DD` | hoy | Fecha fin |

**Respuesta `200`:**
```json
{
  "total": 285000.00,
  "employees": [
    {
      "id": 1,
      "name": "Carlos López",
      "position": "Técnico",
      "salary": 15000.00,
      "days_worked": 22,
      "amount": 15000.00
    }
  ]
}
```

---

## 19. Restaurante

Módulo `restaurant` (planes Pro y Empresa; otro plan recibe `403 module_not_in_plan`). Todo vive bajo `/restaurant`. Las listas acotadas (`stations`, `tables`, `stock_alerts`) devuelven `{ results }` completo, sin paginar. Los endpoints con **idem** aceptan `Idempotency-Key`; los marcados **etag** responden `304` si no cambió nada. Contrato completo: `specs/013-restaurante-comandas/contracts/restaurant-api.md` del workspace.

| Método y ruta | Quién | Descripción |
|---|---|---|
| `GET /restaurant/stations` | todos | Estaciones |
| `POST`, `PATCH /restaurant/stations[/:id]` | encargado o superior | `{ name, is_default, active, position }` |
| `GET /restaurant/tables` | todos, etag | Mesas con su cuenta abierta, `takeouts`, `ready_items` de la persona y `stock_alerts` (solo encargado) |
| `POST`, `PATCH /restaurant/tables[/:id]` | encargado o superior | `{ name, active, position }` |
| `POST /restaurant/checks` | todos | `{ dining_table_id }` o `{ takeout_name }`; `422 table_occupied` |
| `GET /restaurant/checks/:id` | todos, etag | Cuenta con artículos, pagos y `allowed_actions` |
| `GET /restaurant/checks/waiters` | encargado o superior | Personas a quienes reasignar |
| `PATCH /restaurant/checks/:id` | encargado o superior | `{ waiter_id }` |
| `POST /restaurant/checks/:id/cancel` | mesero de la cuenta o encargado | Solo sin artículos mandados |
| `POST`, `PATCH`, `DELETE /restaurant/checks/:id/items[/:item_id]` | todos | Agregar, ajustar o quitar artículos sin mandar; `422 sold_out` |
| `POST /restaurant/checks/:id/rounds` | todos, idem | Manda los artículos sin mandar como una comanda |
| `POST /restaurant/checks/:id/items/:item_id/deliver` | todos | `ready` a `delivered` |
| `POST /restaurant/checks/:id/items/:item_id/cancel` | mesero (nuevo) o encargado | `{ reason }` obligatorio |
| `POST /restaurant/checks/:id/payments` | mesero de la cuenta o encargado, idem | `{ method, amount, reference?, amount_received?, confirm_incomplete? }`; el pago que cubre el saldo cierra la cuenta y devuelve el ticket |
| `POST /restaurant/checks/:id/close` | encargado o superior | Cierra en cero con `{ reason }` |
| `GET /restaurant/stations/:id/board` | todos, etag | Comandas pendientes de la estación |
| `POST /restaurant/stations/:id/items/:item_id/advance` | todos | `new` a `preparing` a `ready` |
| `POST /restaurant/stations/:id/kitchen_orders/:id/advance` | todos | Avanza todos los artículos de la comanda |
| `GET /restaurant/stock_alerts` | encargado o superior | Productos controlados agotados o en su mínimo |

Códigos de error en `error.details.code`: `table_occupied`, `sold_out`, `nothing_to_send`, `reference_required`, `exceeds_balance`, `incomplete_items`, `check_not_open`, `invalid_transition`, `reason_required`, `has_sent_items`, `not_zero_total`, `not_draft`, `waiter_not_member`.

Los tickets de una cuenta salen en `GET /tickets` con `work_order: null`, un bloque `check`, `payment_method` `mixed` si hubo varios métodos y, en el detalle, `payments[]`. Los productos aceptan `station_id` y `tracks_stock`, y `GET /products/menu` suma `available_qty`, `sold_out` y `low`.

---

## Notas adicionales

### Webhook de Stripe — `POST /stripe/webhooks`

Endpoint **público y sin autenticación**. Solo para uso interno de Stripe. No llamar desde la app.

### Flujo de Ticket (automático)

```
WorkOrder → status: "completed"
         → se crea Ticket automáticamente
         → folio asignado: T-000001, T-000002...
         → Ticket puede marcarse como paid o descargarse como PDF
```

### Flujo de Empleado con usuario

```
POST /employees (con email)
  → se crea User con role: "staff", active: false
  → se envía correo "Configura tu contraseña"
  → usuario usa PUT /passwords/update_with_token
  → user.active = true, employee.status = "active"
```
