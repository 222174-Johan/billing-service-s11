# Microservicio de facturación de demostración — Semana 11

**Curso:** Arquitectura del Software (AIS86)  
**Práctica:** Semana 11 — Microservicio de facturación con Supabase  
**Integración:** Aplicativo Flash Sale Lab de Semana 9

## 1. Descripción y alcance

Este repositorio implementa un microservicio independiente para **emitir y consultar comprobantes internos de demostración** asociados con pedidos confirmados. Se ejecuta como una **Supabase Edge Function** sobre HTTPS y persiste sus comprobantes en **PostgreSQL**.

> **Importante:** no realiza cobros, no calcula impuestos, no genera comprobantes electrónicos SUNAT y no procesa datos personales. El estado `issued` significa que se generó un comprobante interno; **no** significa que el pedido haya sido pagado. En S09, `confirmed` indica que el pedido y su stock fueron registrados.

El servicio implementa autenticación entre sistemas mediante el encabezado `X-Billing-Token`, aislamiento entre tiendas, validación estricta de las solicitudes, emisión idempotente y respuesta consistente a reintentos.

## 2. Arquitectura

```text
Navegador S09
     │  REST / JSON
     ▼
FastAPI S09 ──► PostgreSQL S09 (pedido y tarea de facturación)
                         │
                         ▼
                   Worker S09
                         │ HTTPS + X-Billing-Token
                         ▼
            Supabase Edge Function /billing
                         │ supabase-js / API de datos
                         ▼
                PostgreSQL public.invoices
```

El backend de S09 confirma el pedido antes de la facturación remota. El worker consume una tarea con los datos persistidos del pedido y solicita el comprobante. Si el proveedor falla, la compra no se cancela: se conserva un estado local de facturación y se puede reintentar con **el mismo `order_id`, contenido e `Idempotency-Key`**.

S09 es propietario de pedidos, inventario y tareas de facturación. S11 es propietario de los comprobantes. No comparten directamente sus tablas.

## 3. Tecnologías

- **Supabase Edge Functions:** ejecución serverless del backend HTTP.
- **TypeScript / Deno:** lógica de validación, autenticación e idempotencia.
- **PostgreSQL:** persistencia y restricción única `(issuer_id, order_id)`.
- **Supabase CLI 3.0.0:** despliegue de la función.
- **Python 3:** preparación de secretos y pruebas HTTP reproducibles.
- **Git / GitHub:** versionado y entrega del código.

No se requiere Docker local para desplegar S11 por la ruta `--use-api`. Docker sí se usa en el aplicativo S09.

## 4. Estructura del repositorio

```text
billing-service-s11/
├── README.md
├── .gitignore
├── package.json
├── package-lock.json
├── crear_secretos.py
├── probar_billing.py
├── sql/
│   └── invoices.sql
└── supabase/
    ├── config.toml
    └── functions/
        └── billing/
            ├── index.ts
            ├── deno.json
            └── .npmrc
```

Los archivos `billing.secrets.env`, `cliente-propio.env` y `cliente-par.env` se generan o mantienen **únicamente en el equipo local**. No forman parte del repositorio público.

## 5. Requisitos previos

- Cuenta de Supabase y un proyecto propio para facturación.
- Node.js 20 o superior, npm y acceso a Internet.
- Python 3.
- Git.

Desde la raíz del repositorio:

```powershell
npm ci
npx supabase --version
```

La versión esperada de Supabase CLI es `3.0.0`.

## 6. Preparar PostgreSQL y proteger los datos

1. Abrir el proyecto propio en Supabase Dashboard.
2. Ir a **SQL Editor**.
3. Ejecutar `sql/invoices.sql` **solo si la tabla todavía no ha sido creada**. Si ya existe, comprobar primero el esquema y los permisos; no repetir un `CREATE TABLE` sin revisar.
4. Verificar la tabla `public.invoices` en **Table Editor**.

La tabla contiene el identificador de factura, identidad de tienda, identificador de pedido, moneda `PEN`, líneas del comprobante, importe en céntimos, estado, hash de solicitud y fecha de creación. La restricción `UNIQUE (issuer_id, order_id)` garantiza que un mismo pedido de una tienda no genere dos facturas.

La tabla tiene **Row Level Security (RLS) habilitado**, sin políticas públicas. Los roles `anon` y `authenticated` no reciben permisos de lectura o escritura; `service_role` solo necesita `SELECT` e `INSERT`. La función usa una credencial administrativa interna, pero el consumidor S09 **nunca** recibe acceso a la base de datos.

Para verificar RLS:

```sql
SELECT relrowsecurity AS rls_activo,
       (SELECT COUNT(*) FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'invoices') AS numero_politicas
FROM pg_class
WHERE oid = 'public.invoices'::regclass;
```

Resultado esperado: `rls_activo = true` y `numero_politicas = 0`.

## 7. Credenciales y seguridad

La autenticación de las tiendas se realiza con un token distinto para cada consumidor, incluido en el encabezado `X-Billing-Token`. La función asocia cada token a un `issuer_id` privado y filtra todas las lecturas por esta identidad.

Para generar las credenciales **solo en una instalación nueva**:

```powershell
python .\crear_secretos.py
```

El programa crea:

| Archivo privado | Propósito |
| --- | --- |
| `billing.secrets.env` | Mapa `BILLING_CLIENTS` con los tokens del servicio |
| `cliente-propio.env` | Token de la tienda propia (`tienda-a`) |
| `cliente-par.env` | Token para el segundo consumidor (`tienda-b`) |

**No ejecutar el generador sobre una instalación ya configurada ni reemplazar tokens que están en uso sin coordinar su rotación.** No compartir `billing.secrets.env`, claves secretas de Supabase ni contraseñas PostgreSQL. Al compañero se le entrega solamente su token de consumidor por un canal privado.

## 8. Despliegue en Supabase

En PowerShell, desde la raíz del servicio, reemplazar `TU_PROJECT_REF` con el identificador del proyecto Supabase correcto:

```powershell
$PROJECT_REF = "TU_PROJECT_REF"
npx supabase login
npx supabase link --project-ref $PROJECT_REF
npx supabase secrets set --env-file .\billing.secrets.env --remote=$PROJECT_REF
npx supabase functions deploy billing --use-api --remote=$PROJECT_REF
```

La función está configurada en `supabase/config.toml` con `verify_jwt = false` porque usa **autenticación personalizada** mediante `X-Billing-Token`; las rutas protegidas no son públicas.

URL base:

```text
https://TU_PROJECT_REF.supabase.co/functions/v1/billing
```

**Comprobación rápida** (PowerShell):

```powershell
$BASE = "https://TU_PROJECT_REF.supabase.co/functions/v1/billing"
Invoke-RestMethod "$BASE/health"
```

Respuesta esperada: `{ "status": "ok", "service": "billing", "version": "1" }`. Esta prueba solo confirma la ejecución de la función; **no comprueba la conexión con la base de datos**.

## 9. Contrato HTTP

| Método | Ruta relativa | Autenticación | Comportamiento |
| --- | --- | --- | --- |
| `GET` | `/health` | No | `200`: función disponible |
| `POST` | `/invoices` | `X-Billing-Token` | `201`: crea factura; `200`: recupera la misma factura |
| `GET` | `/invoices/{id}` | `X-Billing-Token` | `200`: factura propia; `404`: inexistente o perteneciente a otra tienda |

### Ejemplo de creación

**Encabezados:**

```http
Content-Type: application/json
X-Billing-Token: TOKEN_PRIVADO_DE_LA_TIENDA
Idempotency-Key: 11111111-1111-4111-8111-111111111111
```

**Cuerpo JSON:**

```json
{
  "order_id": "11111111-1111-4111-8111-111111111111",
  "currency": "PEN",
  "items": [
    {
      "product_id": "p1",
      "name": "Producto demo",
      "quantity": 2,
      "unit_price_cents": 2500
    }
  ],
  "total_cents": 5000
}
```

Reglas principales: `order_id` e `Idempotency-Key` deben ser idénticos; `currency` siempre es `PEN`; el monto se representa con **céntimos enteros**; se aceptan de 1 a 6 líneas, con cantidades enteras de 1 a 5; el servidor valida y recalcula el total; no se aceptan campos extra ni cuerpos de más de 32 768 bytes.

Una primera emisión devuelve `201` y `X-Idempotent-Replay: false`. Repetir el mismo pedido con los mismos datos normalizados devuelve `200` y `X-Idempotent-Replay: true`, sin crear una segunda factura. Si se reutiliza el mismo pedido con contenido distinto, devuelve `409` (`IDEMPOTENCY_CONFLICT`).

Otros códigos relevantes: `400` JSON inválido, `401` token incorrecto, `404` no encontrado o ajeno, `405` método no admitido, `413` cuerpo grande, `415` tipo de contenido no admitido, `422` validación y `503` indisponibilidad/configuración del servicio.

## 10. Pruebas del microservicio

Ejecutar:

```powershell
python .\probar_billing.py
```

El script solicita la URL base, el token de `tienda-a` y el de `tienda-b`, **sin mostrarlos**. Verifica 18 casos: salud, autenticación, persistencia, repetición idempotente, consulta, conflicto, valores y campos inválidos, aislamiento entre consumidores, reordenamiento de líneas, cinco solicitudes simultáneas y errores HTTP.

**Evidencia de la ejecución de la práctica (11/11/2026):** `18/18 pruebas superadas`, incluida la comprobación de que cinco llamadas concurrentes generan una sola factura. El script crea tres facturas sintéticas por ejecución. Cada nueva instalación debe repetir sus pruebas y registrar los resultados propios.

Además de la ejecución HTTP, comprobar que los registros aparezcan en `public.invoices` y que la configuración RLS/permisos sea la esperada.

## 11. Integración con Semana 9

S09 configura **en su backend/worker**, y nunca en el navegador, las variables:

```dotenv
BILLING_BASE_URL=https://TU_PROJECT_REF.supabase.co/functions/v1/billing
BILLING_TOKEN=TOKEN_PRIVADO_DE_ESTA_TIENDA
```

El worker llama a `POST /invoices` usando exclusivamente el snapshot persistido del pedido confirmado, con `Idempotency-Key = order.id`. La integración conserva el estado de notificaciones separado del estado de facturación. Una indisponibilidad del servicio S11 no revierte un pedido confirmado; el worker registra el fallo y un reintento manual posterior conserva el mismo pedido.

**Evidencia de integración de la práctica (11/11/2026):** se verificaron pedido confirmado, replay del pedido sin duplicación, comprobante emitido en Supabase y persistencia de `confirmed`. También se probó una caída simulada del proveedor, el estado `failed`, la restauración y la emisión tras reintento manual. El frontend S09 muestra el estado y número del comprobante interno.

## 12. Validación entre compañeros

1. El proveedor A entrega a B únicamente la URL base HTTPS y el token asignado a `tienda-b`.
2. B configura el backend de su propio S09 y crea un pedido confirmado.
3. B consulta su comprobante y repite la emisión: debe recibir el mismo comprobante.
4. A intenta consultar la factura de B con su token A: debe obtener `404`.
5. Ambos **invierten roles**: B despliega su servicio y A lo consume con un token asignado por B.

Esta validación cruzada requiere evidencia de ambos equipos; pasar las pruebas automáticas con dos tokens no sustituye la prueba recíproca real.

## 13. Publicación y evidencias

Antes de publicar ejecutar:

```powershell
git status --short
git add -A
git diff --cached --check
git diff --cached --name-only
git ls-files -- .env billing.secrets.env cliente-propio.env cliente-par.env
```

**La última comprobación no debe imprimir ningún nombre.** No publicar `.env`, `*.env`, `node_modules/`, secretos de Supabase, tokens ni archivos ZIP de respaldos que puedan contener credenciales.

Para la evaluación, conservar capturas del despliegue, consultas SQL de RLS/permisos, las pruebas `18/18`, una factura persistida, el consumo S09→S11, la caída y recuperación, y la validación recíproca. Ocultar siempre los secretos.

## 14. Referencias

- [Guía oficial de Supabase Edge Functions](https://supabase.com/docs/guides/functions)
- [Despliegue de Edge Functions](https://supabase.com/docs/guides/functions/deploy)
- [Secretos en Edge Functions](https://supabase.com/docs/guides/functions/secrets)
- [Row Level Security en Supabase](https://supabase.com/docs/guides/database/postgres/row-level-security)
- **Guía de laboratorio AIS86 — Semana 11**, proporcionada en el curso.
