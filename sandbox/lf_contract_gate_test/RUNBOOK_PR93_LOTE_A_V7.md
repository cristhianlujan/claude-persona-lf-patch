# RUNBOOK — PR #93 · Lote A V7

Fecha: 2026-08-01  
Repositorio: `cristhianlujan/claude-persona-lf-patch`  
Rama: `lf/architecture-v7-hardening`  
Proyecto activo: `mhwmirqcgxxukpctffuv`

## Regla de cambio

No aplicar migraciones ni desplegar Edge desde la rama del PR. El flujo obligatorio continúa siendo: entorno aislado, aplicación ordenada, pruebas positivas y adversariales, readback, auditoría independiente, controles GitHub, merge y despliegue desde `main`.

## Cadena de migraciones V7

1. `20260801175950_prepare_v7_object_owners.sql`
2. `20260801180000_writer_hmac_nonce_v7.sql`
3. `20260801180100_quarantine_compensating_evidence_v7.sql`
4. `20260801180150_trusted_v7_readback_grants.sql`
5. `20260801180200_governance_role_and_rls_v7.sql`
6. `20260801180300_static_audit_corrections_v7.sql`
7. `20260801180305_prepare_idempotency_owner_context.sql`
8. `20260801180310_v7_idempotency_guards.sql`
9. `20260801180315_v7_row_integrity_guards.sql`
10. `20260801180320_cleanup_idempotency_owner_context.sql`
11. `20260801180400_writer_key_rotation_v7.sql`
12. `20260801180500_writer_canonicalization_rls_v7.sql`
13. `20260801180510_writer_full_payload_binding_v7.sql`

Edge permanece en:

`supabase/migrations/edge_functions/lf-github-reconcile-v3-v7/index.ts`

## Contrato HMAC y payload completo

Edge y PostgreSQL calculan exactamente:

```text
payload_hash = SHA-256(canonical_json(payload))
preimage = frame(scope) || frame(execution_id) || frame(payload_hash)
signature = HMAC-SHA256(preimage || ":" || nonce)
frame(value) = utf8_byte_length(value) || "#" || value
```

La migración `180500` eliminó el desplazamiento de componentes `NULL`. La migración `180510` sustituye el preimage campo por campo por un digest del payload completo y elimina el delimitador ambiguo entre componentes.

Reglas del JSON canónico:

- claves limitadas a `[A-Za-z0-9_.-]+`;
- claves ordenadas ascendentemente;
- arrays conservan orden;
- strings usan escape JSON y UTF-8;
- `null` y booleanos conservan semántica JSON;
- números permitidos solo si son enteros seguros de JavaScript;
- valores no representables fallan en cerrado;
- cualquier modificación de un campo o valor anidado cambia el preimage;
- `key_id` no forma parte del mensaje firmado y Edge no necesita conocerlo.

El prefijo de longitud usa bytes UTF-8. Los valores con `:` son válidos y no pueden cambiar los límites entre componentes.

La firma RPC de los writers no cambia.

## Keystore y RLS

La clave no se guarda en Vault porque `service_role` puede acceder a secretos del Vault en el proyecto observado.

El keystore:

- permanece propiedad de `postgres`;
- mantiene RLS y FORCE RLS;
- tiene una política explícita para `postgres`;
- no depende de que `postgres` conserve `BYPASSRLS`;
- no concede lectura ni escritura a roles API;
- bloquea `DELETE` y `TRUNCATE`;
- conserva material e identidad inmutables.

La tabla de nonces:

- permanece propiedad de `lf_writer_verifier_v7`;
- mantiene RLS y FORCE RLS;
- exige `key_id is not null` para todo INSERT nuevo;
- permite `key_id` nulo únicamente en filas históricas anteriores a `180400`;
- bloquea `TRUNCATE`.

## Lifecycle y rotación

Estados permitidos:

```text
PREPARED → ACTIVE → RETIRING → RETIRED
```

Invariantes:

- una sola `ACTIVE`;
- una sola `PREPARED`;
- una sola `RETIRING`;
- `active=true` únicamente para la fila `ACTIVE`;
- material e identidad inmutables;
- aceptación de `RETIRING` limitada a diez minutos;
- retiro solo después de vencer la ventana y sin nonces vigentes ligados a esa generación;
- una fila `RETIRED` conserva `retiring_until >= retiring_at`.

Funciones administrativas, ejecutables únicamente por `postgres`:

- `private.fn_install_writer_hmac_key_v7`
- `private.fn_writer_hmac_challenge_v7`
- `private.fn_promote_writer_hmac_key_v7`
- `private.fn_retire_writer_hmac_key_v7`

Estado no secreto:

```sql
select private.fn_writer_key_rotation_status_v7();
```

Valores previstos:

- `READY`
- `PREPARED_PENDING`
- `OVERLAP_ACTIVE`
- `RETIREMENT_DUE`
- `ACTIVE_KEY_COUNT_INVALID`
- `KEY_SEPARATION_INVALID`

`RETIREMENT_DUE` es un bloqueo operativo explícito. No debe interpretarse como ausencia de clave.

## Pruebas obligatorias

Ejecutar en un entorno aislado:

- `sandbox/lf_contract_gate_test/PR93_WRITER_V7_ADVERSARIAL_TESTS.sql`
- `sandbox/lf_contract_gate_test/PR93_CA_N36_N38_ADVERSARIAL_TESTS.sql`
- `sandbox/lf_contract_gate_test/PR93_EDGE_CANONICAL_PAYLOAD_TEST.ts`
- `sandbox/lf_contract_gate_test/PR93_V7_READBACK.sql`
- `sandbox/lf_contract_gate_test/PR93_V7_HARDENING_READBACK.sql`
- `sandbox/lf_contract_gate_test/PR93_V7_PAYLOAD_BINDING_READBACK.sql`

La batería exige:

1. Control positivo del verificador privado.
2. Control positivo del writer público.
3. Replay rechazado.
4. Nonce expirado y futuro rechazados.
5. Firma incorrecta rechazada.
6. Claims ausentes y `anon` rechazados.
7. Vector canónico compartido con SHA-256 idéntico en Edge y PostgreSQL.
8. Orden de claves irrelevante para el digest.
9. Distribuciones distintas de `:` producen preimages distintos.
10. Mutaciones de `artifact_path`, `merged`, `failure_reasons` y detalles anidados cambian el preimage.
11. Números fraccionarios y enteros fuera del rango seguro son rechazados.
12. Prueba 13 bajo `SET LOCAL ROLE service_role`.
13. `RESET ROLE` protegido por manejador de excepción.
14. Cero nonce, reconciliación y evento ante una firma fabricada.
15. Firma legítima con nonce expirado rechazada sin efectos.
16. Desafío de una clave `PREPARED`.
17. Aceptación de la clave anterior dentro de `RETIRING` y de la nueva `ACTIVE`.
18. Registro del `key_id` que validó cada nonce.
19. `ROLLBACK` total en las baterías SQL.

No interpretar ningún control negativo si falla alguno de los dos controles positivos.

## Rotación operativa futura

1. Generar la clave fuera del repositorio y de cualquier canal de chat.
2. Instalarla como `PREPARED`.
3. Comparar el desafío PostgreSQL con un HMAC calculado localmente por el operador seguro.
4. Promoverla; la clave anterior pasa a `RETIRING`.
5. Cambiar el secreto Edge `LF_RECONCILIATION_WRITER_HMAC_V7`.
6. Ejecutar inmediatamente un control positivo a través del writer público.
7. Ante divergencia, revertir Edge a la clave anterior dentro de la ventana de diez minutos.
8. Consultar `private.fn_writer_key_rotation_status_v7()`.
9. Al vencer la ventana y no existir nonces vigentes, ejecutar obligatoriamente `fn_retire_writer_hmac_key_v7`.
10. Confirmar que el estado vuelve a `READY`.
11. Ejecutar readback completo.

No dejar una clave vencida en `RETIRING`: produce `RETIREMENT_DUE`, bloquea readiness y evita una siguiente promoción.

## Readback mínimo

- Owner del keystore: `postgres`.
- Owner de nonces: `lf_writer_verifier_v7`.
- RLS/FORCE RLS activos.
- Política explícita de keystore para `postgres`.
- Cero acceso API al keystore y funciones privadas.
- Una sola clave `ACTIVE`.
- Ninguna `RETIRING` vencida.
- Estado de rotación explícito.
- Política de INSERT de nonces exige `key_id`.
- Nonces nuevos con `key_id` registrado.
- Writers públicos usan helpers canónicos.
- Helpers activos usan hash de payload completo y framing por longitud.
- Roles API no ejecutan helpers privados.
- Writers V5/V6 no ejecutables por roles API.
- Writers públicos V7 ejecutables solo por `service_role`.
- Triggers críticos, incluidos los de TRUNCATE, en estado `ALWAYS`.
- V8 sin dependencia de controles V5/V6.

## Bloqueos externos

- No existe ejecución SQL en entorno aislado.
- Falta auditoría independiente del head final.
- Falta ruleset nativo de `main` y aprobación de identidad distinta del autor.
- `supabase_admin` debe resolver la membresía residual y los grants API del esquema `net`.
- La exposición del esquema Vault permanece administrativamente abierta, aunque la clave del writer no se almacena allí.

## Prohibiciones

- No desplegar desde la rama del PR.
- No instalar claves mediante contenido versionado.
- No almacenar la clave en Vault mientras `service_role` conserve acceso.
- No aceptar evidencia compensatoria para PASS o promoción.
- No regenerar baseline antes del merge y la reconciliación posterior.
- No fusionar por checks verdes solamente.
