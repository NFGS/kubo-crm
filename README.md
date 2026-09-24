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
| GET | `/api/v1/health` | Estado del servicio y de la base |

## Cifrado de datos personales

| Aspecto | Implementación |
| --- | --- |
| Algoritmo | AES-256-GCM (confidencialidad + autenticidad) |
| Formato | `base64(iv ‖ tag ‖ ciphertext)` en una sola columna |
| Búsqueda | Índice ciego HMAC-SHA256 normalizado (`document_number_bidx`) |
| Minimización | Los listados devuelven `******432`; solo el detalle revela el dato |
| Rotación | La clave llega por `KUBO_FIELD_ENCRYPTION_KEY` (32 bytes en hex) |

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
ruby test/field_cipher_test.rb    # no requiere base de datos
```

Cubren: ida y vuelta del cifrado, IV aleatorio (dos cifrados difieren), detección
de manipulación, determinismo del índice ciego y enmascarado.

## Decisiones de diseño

- **La identidad no se valida aquí**: llega verificada desde el API Gateway en las
  cabeceras `X-User-Id` y `X-Tenant-Id`. El servicio solo es alcanzable en la red
  privada de contenedores.
- **Sin `default_scope`**: el filtro por negocio y por borrado lógico es explícito
  en cada consulta, para que nunca haya sorpresas ocultas. Como segunda barrera,
  **RLS está activo con `FORCE`**: el `around_action` de `ApplicationController`
  fija `app.tenant_id` en una transacción por petición y una consulta sin contexto
  devuelve cero filas (ADR-0010).
- **`secret_key_base` nunca en el repositorio**: en producción llega por variable
  de entorno; en desarrollo se genera uno aleatorio por arranque.
