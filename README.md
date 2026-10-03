# kubo-crm

Servicio de clientes (CRM) de Kubo. Demuestra el cifrado de datos personales a
nivel de campo y la búsqueda sobre datos cifrados mediante índices ciegos.

| Campo | Valor |
| --- | --- |
| Stack | Ruby 3.4 · Rails 8 (API) · Puma · ActiveRecord |
| Base de datos | PostgreSQL 17 (`kubo_crm`) |
| Puerto | 8082 (contenedor) · 9082 (host) |
| Ruta base | `/api/v1` |

## Endpoints

| Método | Ruta | Descripción |
| --- | --- | --- |
| GET | `/api/v1/customers` | Listado (documento y teléfono **enmascarados**) |
| GET | `/api/v1/customers/:id` | Detalle (valores completos descifrados) |
| POST | `/api/v1/customers` | Crear cliente |
| PATCH | `/api/v1/customers/:id` | Actualizar cliente |
| DELETE | `/api/v1/customers/:id` | Borrado lógico (`deleted_at`) |
| GET | `/api/v1/customers/stats` | Conteos por etapa y cartera |
| GET | `/api/v1/customers/by-document/:document` | Búsqueda exacta por documento (índice ciego) |
| GET | `/api/v1/health` | Estado del servicio y de la base |

## Cifrado de datos personales

| Aspecto | Implementación |
| --- | --- |
| Algoritmo | AES-256-GCM (confidencialidad + autenticidad) |
| Formato | `v1:<key_id>:base64(iv ‖ tag ‖ ciphertext)`: el dato dice con qué llave se escribió |
| Anillo | `KUBO_FIELD_ENCRYPTION_KEYS` = `id:hex,id:hex,…` con la llave nueva al frente; `KUBO_FIELD_ENCRYPTION_KEY` queda como `default` para los valores anteriores al anillo |
| Búsqueda | Índice ciego HMAC-SHA256 normalizado (`document_number_bidx`), con su propia llave `KUBO_BLIND_INDEX_KEY` |
| Minimización | Los listados devuelven `******432`; solo el detalle revela el dato |
| Rotación | `rake kubo:rotate_field_keys` re-cifra por lotes con la llave nueva y recalcula el índice ciego si su llave cambió; lo ilegible se cuenta y **nunca se destruye** (ADR-0019) |

Un valor enmascarado que llegue por error en un `PATCH` se ignora: no puede
re-cifrarse la máscara y pisar el documento real.

Verificación manual:

```bash
# El valor cifrado en la base no se parece al documento real
psql "postgres://kubo_crm@localhost:5433/kubo_crm" \
  -c "select name, document_number_encrypted, document_number_bidx from customers limit 3"
```

## Modelo de datos

```
customers
├── id                        uuid  PK
├── tenant_id                 uuid  (aislamiento por negocio)
├── name, email, city, address, notes
├── document_number_encrypted text  ← AES-256-GCM
├── document_number_bidx      text  ← HMAC-SHA256 (búsqueda exacta)
├── phone_encrypted / phone_bidx
├── stage                     LEAD | PROSPECT | CUSTOMER
├── credit_limit              numeric(14,2)
├── deleted_at                timestamptz (borrado lógico)
└── created_at / updated_at
```

## Pruebas

```bash
./kubo-infra/scripts/crm-tests.sh
```

**27 pruebas**: 13 puras de cifrado (ida y vuelta, IV aleatorio, manipulación,
índice ciego, enmascarado, anillo y valores heredados) y 14 de integración contra
PostgreSQL real como rol de la aplicación: aislamiento RLS entre negocios,
rotación de llaves (incluidos los valores sin prefijo), recálculo del índice
ciego y el contrato HTTP del recurso (listado enmascarado, detalle que revela,
búsqueda por documento, alta, archivo y sonda de salud). La corrida va con
**SimpleCov** y exige ≥ 80 % de líneas (hoy 92 %).

## Decisiones de diseño

- **La identidad no se autentica aquí, pero sí se valida**: llega verificada desde
  el API Gateway en `X-User-Id` y `X-Tenant-Id`; el servicio rechaza un
  `X-Tenant-Id` que no sea un UUID (400 `INVALID_TENANT`) y solo es alcanzable en
  la red privada de contenedores (mTLS).
- **Sin `default_scope`**: el filtro por negocio y por borrado lógico es explícito
  en cada consulta, para que nunca haya sorpresas ocultas. Como segunda barrera,
  **RLS está activo con `FORCE`**: el `around_action` de `ApplicationController`
  fija `app.tenant_id` en una transacción por petición y una consulta sin contexto
  devuelve cero filas (ADR-0010).
- **`secret_key_base` nunca en el repositorio**: en producción llega por variable
  de entorno; en desarrollo se genera uno aleatorio por arranque.

## Observabilidad (Fase 2)

Trazas OpenTelemetry con `opentelemetry-instrumentation-rails`: el inicializador
solo se activa si existe `OTEL_EXPORTER_OTLP_ENDPOINT`, de modo que el servicio
arranca igual sin collector.
