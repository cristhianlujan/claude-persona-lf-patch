# PG-00.C3.6-B — B2/B3/B4: límites y criterios de calificación

**Estado:** `DESIGN_ONLY / NO_GO_WRITE`. Documento de ingeniería, no decisión de owner ni migración ejecutable.

## B2 — Identidades de digest

Contrato observado en `main`:
- `supabase/migrations/edge_functions/lf-github-reconcile-v3-v7/canonical_payload_v7.ts`: representación determinista de JSON con claves ASCII y números enteros seguros JS. **No** es una prueba de conformidad con RFC 8785.
- Store #3365: `catalog_jsonb_sha256` está calculado a partir de `catalog_json::text` PostgreSQL. No asumir que el digest coincide con bytes JSON de GitHub o canonicalización JS/Python.
- `pg00_c36_b2_digest_lab_v1.py` mantiene por separado: SHA-256 de bytes fuente, SHA-256 de bytes release, SHA-256 diagnóstico Python y, cuando se suministra, SHA-256 del texto de readback PostgreSQL. Todos son informativos y el resultado conserva `BLOCKED / NONE`.

**Decisión D-C36-03 pendiente:** aprobar algoritmo y versión de JSON canónico, límites numéricos/Unicode, esquema de prueba y traducción al digest del store. Se requiere corpus verificable cross-language y PostgreSQL desechable antes de cualquier atestación efectiva.

## B3 — Reserva, versionado y antirreplay

Reutilizar como precedente `docs/migrations/POLICY_MIGRATION_APPLY_V1.md`: identidad exacta de migración, bloqueo de ledger y comprobación de versión dentro de transacción. Ese contrato no reserva ni consume automáticamente una **propuesta de catálogo**.

Máquina de estados candidata, todavía sin implementador autorizado:

`PROPOSED -> APPROVED -> RESERVED_BY_TRAIN -> APPLIED_VERIFIED -> CONSUMABLE`

- Clave única de propuesta: `proposal_id` y su vínculo inmutable (source SHA, source digest, release digest, CHG, versión, migration path, política).
- En una única transacción del executor aprobado: reconsultar aprobación actual y estado no revocado; bloquear propuesta y versión; verificar que `catalog_version` sea monótona, que el par versión/digest no exista y que ninguna propuesta ya consumida pueda repetirse.
- Si dos ejecutores intentan mismo proposal/version: solo el que logra el lock y mantiene todas las condiciones puede continuar; el otro debe bloquear con razón explícita.
- Si fallan apply o escritura de ledger: rollback atómico. Tras apply efectivo, recuperación `fail-forward` con el mismo blob; jamás retimestamp/replay silencioso.

**Decisión D-C36-04 pendiente:** semver exacto, condición de unicidad, transiciones de estado, expiración/revocación, qué ocurre con `VALIDAR_CON_LEGAL` y contrato de persistencia/transacción. No escribir SQL de aplicación sin esas decisiones.

## B4 — Extensión de verificación postapply

Reutilizar `sandbox/lf_contract_gate_test/train_receipt_verifier/verify_train_receipt.py` de `main`. Su `verify_snapshot` contrasta recibo Train, ejecución, pasos, ledger y GitHub para el scope general de migración; no lo copiar ni degradar.

Diseñar un adaptador read-only que, **solo tras** `verify_snapshot == PASS` sobre evidencia autenticada, haga readback del catálogo vinculado al mismo PR/commit/versión, y contraste:
- `proposal_id`, release catalog version, estado publicado y SHA de referencia;
- digest que corresponde **a la representación y algoritmo aprobados**;
- unicidad de fila/ledger y concordancia entre identificadores de Train y propuesta;
- permiso de consumo PG-01/C6 como condición independiente (nunca inferida por solo insertar una fila).

Los datos inyectados por fixtures no constituyen evidencia de proveedor, y un `PASS` histórico no debe reutilizarse. Si el recibo general no pasa, o la fila/ledger no coinciden, marcar `BLOCKED`, nunca `CONSUMABLE_BY_PG`.

**Decisión D-C36-06 pendiente:** origen autenticado de readback, esquema de fila definitivo y mecanismo de pin para el consumidor.

## Compuerta B5

El trigger incondicional `PG00_C3_UNTRUSTED_INSERT_FORBIDDEN` del PR #3365 sigue prohibiendo toda inserción. **No** desactivarlo, no ejecutarlo por otro canal y no inventar privilegios: el mecanismo de entrada privilegiada del Train precisa diseño y aprobación del equipo Train/DBA (D-C36-05). Mientras no exista, cualquier escritor real es `NO_GO_WRITE`.

## Evidencia y siguiente auditoría

B2 contiene pruebas de diferencias de representación. B3 y B4 se documentan para decisión; no se implementó ledger persistente ni adaptador live. Se exige auditoría independiente de los módulos y una decisión de owner para D-C36-01..06, separando explícitamente `GO_ISOLATED_DESIGN` de `GO_WRITE`.
