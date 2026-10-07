# kubo-crm
[!\[CI](https://github.com/NFGS/kubo-crm/actions/workflows/ci.yml/badge.svg)\]([https://github.com/NFGS/kubo-crm/actions/workflows/ci.yml](https://github.com/NFGS/kubo-crm/actions/workflows/ci.yml))
> Parte del proyecto **Kubo** — [kubo-workspace](https://github.com/NFGS/kubo-workspace) (ERP + CRM autoalojable para PYMES).
Servicio de clientes (CRM) de Kubo. Demuestra el cifrado de datos personales a
nivel de campo y la búsqueda sobre datos cifrados mediante índices ciegos.
<table header-row="true">
<tr>
<td>Campo</td>
<td>Valor</td>
</tr>
<tr>
<td>Stack</td>
<td>Ruby 3.4 · Rails 8 (API) · Puma · ActiveRecord</td>
</tr>
<tr>
<td>Base de datos</td>
<td>PostgreSQL 17 (`kubo_crm`)</td>
</tr>
<tr>
<td>Puerto</td>
<td>8082 (contenedor) · 9082 (host)</td>
</tr>
<tr>
<td>Ruta base</td>
<td>`/api/v1`</td>
</tr>
</table>
## Endpoints
<table header-row="true">
<tr>
<td>Método</td>
<td>Ruta</td>
<td>Descripción</td>
</tr>
<tr>
<td>GET</td>
<td>`/api/v1/customers`</td>
<td>Listado (documento y teléfono **enmascarados**)</td>
</tr>
<tr>
<td>GET</td>
<td>`/api/v1/customers/:id`</td>
<td>Detalle (valores completos descifrados)</td>
</tr>
<tr>
<td>POST</td>
<td>`/api/v1/customers`</td>
<td>Crear cliente</td>
</tr>
<tr>
<td>PATCH</td>
<td>`/api/v1/customers/:id`</td>
<td>Actualizar cliente</td>
</tr>
<tr>
<td>DELETE</td>
<td>`/api/v1/customers/:id`</td>
<td>Borrado lógico (`deleted_at`)</td>
</tr>
<tr>
<td>GET</td>
<td>`/api/v1/customers/stats`</td>
<td>Conteos por etapa y cartera</td>
</tr>
<tr>
<td>GET</td>
<td>`/api/v1/customers/by-document/:document`</td>
<td>Búsqueda exacta por documento (índice ciego)</td>
</tr>
<tr>
<td>GET</td>
<td>`/api/v1/health`</td>
<td>Estado del servicio y de la base</td>
</tr>
</table>
## Cifrado de datos personales
<table header-row="true">
<tr>
<td>Aspecto</td>
<td>Implementación</td>
</tr>
<tr>
<td>Algoritmo</td>
<td>AES-256-GCM (confidencialidad + autenticidad)</td>
</tr>
<tr>
<td>Formato</td>
<td>`v1:<key_id>:base64(iv ‖ tag ‖ ciphertext)`: el dato dice con qué llave se escribió</td>
</tr>
<tr>
<td>Anillo</td>
<td>`KUBO_FIELD_ENCRYPTION_KEYS` = `id:hex,id:hex,…` con la llave nueva al frente; `KUBO_FIELD_ENCRYPTION_KEY` queda como `default` para los valores anteriores al anillo</td>
</tr>
<tr>
<td>Búsqueda</td>
<td>Índice ciego HMAC-SHA256 normalizado (`document_number_bidx`), con su propia llave `KUBO_BLIND_INDEX_KEY`</td>
</tr>
<tr>
<td>Minimización</td>
<td>Los listados devuelven `******432`; solo el detalle revela el dato</td>
</tr>
<tr>
<td>Rotación</td>
<td>`rake kubo:rotate_field_keys` re-cifra por lotes con la llave nueva y recalcula el índice ciego si su llave cambió; lo ilegible se cuenta y **nunca se destruye** (ADR-0019)</td>
</tr>
</table>
Un valor enmascarado que llegue por error en un `PATCH` se ignora: no puede
re-cifrarse la máscara y pisar el documento real.
Verificación manual:
```bash
# El valor cifrado en la base no se parece al documento real
psql "postgres://kubo_crm@localhost:5433/kubo_crm" \
  -c "select name, document_number_encrypted, document_number_bidx from customers limit 3"
```
## Modelo de datos
```javascript
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
**34 pruebas**: 13 puras de cifrado (ida y vuelta, IV aleatorio, manipulación,
índice ciego, enmascarado, anillo y valores heredados) y 21 de integración contra
PostgreSQL real como rol de la aplicación: aislamiento RLS entre negocios,
rotación de llaves (incluidos los valores sin prefijo y los ilegibles),
recálculo del índice ciego y el contrato HTTP completo del recurso (listado
enmascarado, detalle que revela, búsqueda por texto y por documento, alta,
archivo, validaciones, 404, tenant inválido y sonda de salud, incluida la
caída de la base). La corrida va con **SimpleCov** y exige ≥ 80 % de líneas
(hoy 100 %).
## Decisiones de diseño
- **La identidad no se autentica aquí, pero sí se valida**: llega verificada desde
	el API Gateway en `X-User-Id` y `X-Tenant-Id`; el servicio rechaza un
	`X-Tenant-Id` que no sea un UUID (400 `INVALID_TENANT`) y solo es alcanzable en
	la red privada de contenedores (mTLS).
- **Sin ****`default_scope`**: el filtro por negocio y por borrado lógico es explícito
	en cada consulta, para que nunca haya sorpresas ocultas. Como segunda barrera,
	**RLS está activo con ****`FORCE`**: el `around_action` de `ApplicationController`
	fija `app.tenant_id` en una transacción por petición y una consulta sin contexto
	devuelve cero filas (ADR-0010).
- **`secret_key_base`**** nunca en el repositorio**: en producción llega por variable
	de entorno; en desarrollo se genera uno aleatorio por arranque.
## Observabilidad (Fase 2)
Trazas OpenTelemetry con `opentelemetry-instrumentation-rails`: el inicializador
solo se activa si existe `OTEL_EXPORTER_OTLP_ENDPOINT`, de modo que el servicio
arranca igual sin collector.
