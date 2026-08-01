# HANDOFF CONSOLIDADO PARA GPT — LF / PR #93 / LOTE 1

Emitido: 2026-08-01
Origen: sesión Claude Web, motor de remediación LF
Estado del lote: SQL versionado, NOT_EXECUTED
Destino: insumo documental. GPT no ejecuta, no escribe, no decide.

---

## 0. Reglas para quien lea este documento

1. Ningún estado almacenado es evidencia: `passed`, `authoritative`, `closure_ready`, `edge_reconciler_v6_ready` no prueban nada.
2. No inventar contenido de archivos del repositorio. Si no lo tienes, dilo.
3. No proponer DDL ni DML para ejecutar en el entorno productivo.
4. No fusionar el PR #93. No regenerar baseline.
5. No emplear los cinco términos en mayúsculas que rechaza el CI `lf-contract-check`. La lista está en `.github/workflows/lf-contract-check.yml`; no se transcribe aquí para que este archivo pueda versionarse sin disparar el gate.
6. No declarar cierre operativo ni PASS de nada que no se haya ejecutado.

---

## 1. Contexto

- Supabase: `mhwmirqcgxxukpctffuv`
- Repo: `cristhianlujan/claude-persona-lf-patch`
- PR #93, rama `lf/architecture-v7-hardening`, commit `fdf738e6dad136703d1b86828b1b5abdd320b9a9`. **Abierto. No fusionar.**
- Lote de trabajo: LOTE 1 = CA-N22 + CA-N23, tratados juntos.
- Decisiones del owner: BQ-1 = B (solo versionar SQL, sin rama con costo, sin hotfix en el entorno productivo) · BQ-2 = clave en tabla privada con rol dedicado, no Vault · BQ-3 = instalación y rotación en dos fases con `key_id`, aceptación doble temporal y desafío HMAC.

---

## 2. Hechos verificados en el entorno productivo

Obtenidos por consultas de solo lectura. No interpretar ni sustituir.

| Hecho | Valor | Fuente |
|---|---|---|
| `private.fn_verify_reconciliation_writer_token_v5` owner | `lf_governance_owner_v3` | `pg_proc` + `pg_get_userbyid` |
| Misma función, SECURITY DEFINER | `true` | `pg_proc.prosecdef` |
| Misma función, `search_path` | `pg_catalog, private, extensions` | `pg_proc.proconfig` |
| md5 del cuerpo de la función V5 | `ad952d4804af2a3112cb696d5f8ee230` | `md5(pg_proc.prosrc)` |
| `private.lf_reconciliation_writer_nonces_v6` owner | `postgres` | `pg_class` |
| RLS / FORCE RLS de esa tabla | `false` / `false` | `pg_class` |
| Grants sobre esa tabla | solo `postgres` | `information_schema.role_table_grants` |
| `has_table_privilege('lf_governance_owner_v3', nonces_v6, 'INSERT')` | `false` | consulta directa |
| Filas en nonces v6 | `0` | `count(*)` |
| Filas en `private.lf_reconciliation_writer_auth_v5` | `1` | `count(*)` |
| `private.lf_writer_hmac_keys_v7` | **no existe** | `pg_class` |
| rol `lf_writer_verifier_v7` | **no existe** | `pg_roles` |
| Única función `%v7%` presente | `private.fn_guard_schema_fingerprint_baseline_v7` | `pg_proc` |
| `v_lf_architecture_closure_v8` | existe, owner `postgres` | `pg_class` |
| `service_role` USAGE en `vault` | `true` | `has_schema_privilege` |
| `service_role` SELECT en `vault.secrets` y `vault.decrypted_secrets` | `true` / `true` | `has_table_privilege` |
| `lf_governance_owner_v3` acceso a `vault` | `false` | `has_schema_privilege` |
| `vault.secrets` | `0` filas | `count(*)` |
| `postgres.rolinherit` | `true` | `pg_roles` |
| `lf_governance_owner_v3.rolbypassrls` | `false` | `pg_roles` |
| pgcrypto instalado en esquema | `extensions` | `pg_extension` |
| Último `lf_eventos.id` | `3211` | `max(id)` |

Métricas de cierre en el momento del readback:
`artifact_count=64`, `pass_v3_count=0`, `judges_pass_v3=0/13`, `github_pass_count=0`,
`latest_gate_tests=64`, `passed_gate_tests=0`, `failed_gate_tests=64`,
`quarantined_events=1789`, `internal_control_ready=false`, `external_blocker_count=1`,
`closure_ready=false`, `computed_closure_status=NOT_READY`.

Este estado es fail-closed. **No es prueba de que V7 funcione.**

---

## 3. Hallazgos confirmados

### CA-N22 — CONFIRMADO
La función verificadora V5 es propiedad de `lf_governance_owner_v3` e inserta en una tabla propiedad de `postgres` sobre la que ese rol no tiene ningún privilegio. El `insert` falla siempre, el `exception when others then return false` lo absorbe, y la función no puede devolver `true` bajo ninguna entrada. Ruta V6 muerta: `nonces_consumed=0`, `v6_rows=0`.

La raíz no es un grant faltante: es una identidad partida entre el dueño de la función y el dueño de la tabla.

### CA-N23 — CONFIRMADO
Firma literal en el código: `encode(digest(convert_to(preimage||':'||writer_token,'UTF8'),'sha256'),'hex')`. Sin clave.

Agravante verificado y no recogido en el enunciado original: **`p_writer_token` lo aporta el propio llamante** y la expiración se deriva de él (`split_part(token,'.',2)`). Un portador de `service_role` fabrica token, firma y ventana temporal. No es una firma débil: no existe.

### CA-N29 — HALLAZGO NUEVO, severidad ALTA
`service_role` puede leer `vault.secrets` y `vault.decrypted_secrets` en este proyecto. Colocar allí la clave HMAC la deja accesible exactamente al actor del modelo de amenaza de CA-N23. Además `lf_governance_owner_v3` no tiene acceso a `vault`, por lo que la ruta ni siquiera sería funcional. Revocar esa exposición requiere `supabase_admin`: bloqueo externo.

---

## 4. Entregable producido (versionado, no ejecutado)

Siete archivos, destino sugerido `sandbox/lf_contract_gate_test/lote1/`:

| Archivo | Contenido |
|---|---|
| `20260801_0001_lf_writer_hmac_v7_role_and_keystore.sql` | Rol `lf_writer_verifier_v7` (NOLOGIN, NOINHERIT, NOBYPASSRLS) + `private.lf_writer_hmac_keys_v7` con RLS + FORCE + política `current_user='lf_writer_verifier_v7'`, índice único parcial de clave ACTIVE, trigger `ENABLE ALWAYS` que bloquea DELETE |
| `20260801_0002_lf_reconciliation_writer_nonces_v7.sql` | `private.lf_reconciliation_writer_nonces_v7` propiedad del mismo rol, RLS + FORCE, PK como control de consumo único, FK a `key_id`, CHECK de TTL máximo 10 minutos, trigger `ENABLE ALWAYS` append-only |
| `20260801_0003_fn_verify_reconciliation_writer_token_v7.sql` | Verificador HMAC con clave, `search_path=''`, preimage canónico compuesto por el servidor, **sin handler catch-all** |
| `20260801_0004_lf_writer_hmac_v7_rotation.sql` | `fn_install` / `fn_writer_hmac_challenge` / `fn_promote` / `fn_retire` |
| `PR93_LOTE1_READBACK.sql` | 7 bloques de solo lectura con valor esperado por campo |
| `RUNBOOK_LOTE1_KEY_INSTALL_V7.md` | Rotación en cuatro fases sin transportar la clave por chat |
| `LOTE1_GUARDS_Y_EVIDENCIA.md` | Evidencia de origen, guards de idempotencia, plantilla de `lf_eventos` no ejecutada |

### Decisiones de diseño relevantes

1. **Identidad unificada.** Función, almacén de claves y tabla de nonces pertenecen al mismo rol dedicado. `owner_can_insert=true` pasa a ser estructural en lugar de depender de un grant que alguien puede revocar.
2. **Preimage canónico del lado servidor.** `canonical := preimage || \n || writer_token || \n || key_id`, firmado con `extensions.hmac(..., 'sha256')`. El llamante deja de controlar lo que se firma. Edge V7 debe reproducirlo byte a byte.
3. **Sin catch-all.** El `exception when others` de V5 es la causa de que CA-N22 sobreviviera tres despliegues. En V7 un fallo de infraestructura se propaga; `false` significa solo fallo de autenticación o replay.
4. **Prefijos disjuntos.** Alcances V7 `reconciliation-v7:` y `gate-v7:`. La evidencia V5/V6 no puede reutilizarse por construcción.
5. **Desafío de rotación acotado.** Formato cerrado `rotation-check-v7:<UUIDv4>`, disjunto de los prefijos operativos, para que la respuesta nunca sea una firma válida.

---

## 5. Límites declarados del entregable

| Ítem | Clasificación |
|---|---|
| CA-N22 / CA-N23 / CA-N29 diagnosticados | RUNTIME_VERIFIED |
| CA-N22 / CA-N23 corregidos | NOT_EXECUTED |
| Resolución de `digest` bajo `search_path=''` | NOT_EXECUTED — pgcrypto está en `extensions`, puede requerir calificar `extensions.digest`. Verificar en entorno aislado |
| Coincidencia de preimage Edge / PostgreSQL | NOT_AUDITABLE — requiere el código de la función Edge V7 |
| Pruebas 7–13 del informe | NOT_AUDITABLE — ver sección 6 |
| Riesgo de divergencia clave Edge ↔ PostgreSQL | Abierto. Probado solo en el instante del desafío |
| Administrador PostgreSQL dentro de la frontera de confianza | Residuo declarado de CA-N06. `fn_install` y `fn_challenge` tienen grant a `postgres`. Se cierra en LOTE 3, no aquí |

---

## 6. Lo que se solicita a GPT

El owner indicó que GPT ya aportó este material. **No llegó a la sesión de Claude**: sin adjunto, sin texto pegado, directorio de cargas vacío. No se reconstruyó por inferencia.

Se requiere, en texto literal y sin reformular:

**A.** Definición de las pruebas 7–13 del informe `AUDITORIA_ADVERSARIAL_LF_v2.0_PR93.md`.

**B.** Contenido de `sandbox/lf_contract_gate_test/PR93_WRITER_V7_ADVERSARIAL_TESTS.sql`.

**C.** Referencias exactas del commit `fdf738e6` para CA-N22 y CA-N23: archivo y líneas. Si el PR #93 ya resuelve ambos, indicar dónde, para evaluar si el entregable de la sección 4 duplica un activo existente o lo complementa.

**D.** Diseño de detección de divergencia de clave entre Edge y PostgreSQL: contador de fallos por `key_id` o desafío programado. Se propone como backlog, no como control existente.

Si algún punto no está disponible, responder `NO_DISPONIBLE` en lugar de aproximarlo.

---

## 7. Criterio de aceptación del LOTE 1

| Término | Estado |
|---|---|
| `owner_can_insert=true` | Satisfecho por diseño, verificable estáticamente. Sin ejecución |
| Firma con clave no legible por `service_role` | Satisfecho por diseño. Sin ejecución |
| Pruebas 7–13 reejecutadas con resultado concluyente | **ABIERTO** |

El lote **no se declara cumplido**.

---

## 8. Fuera de alcance

CA-N05, CA-N28 (RLS en tablas `*_v4`), CA-N06 (membresías de `postgres`, `rolinherit`, BYPASSRLS), CA-N25 (192 filas con control compensatorio), CA-N26 (política de despliegue posterior al merge), CA-N29 (revocación de `vault`, requiere `supabase_admin`), ruleset nativo de `main`, revisor de identidad distinta del autor, grants del esquema `net`, receptor de alertas externo, código de las funciones Edge.

---

## 9. Confirmación

En la sesión que produjo este documento no se escribió en Supabase, no se ejecutó DDL ni DML, no se fusionó el PR #93, no se regeneró baseline, no se reveló material de clave y no se modificó el estado operativo. `pass_v3_count` permanece en `0/64` y `computed_closure_status` en `NOT_READY`.
