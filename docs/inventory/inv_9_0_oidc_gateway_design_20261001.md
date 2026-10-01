# INV-9.0 — Diseño detallado de la puerta OIDC A′

Fecha: 2026-10-01  
Base exacta: `main@21bc55aa18eaa57553cef54bf56a6f5ca5fceef8`  
Tipo: D (diagnóstico/diseño; sin cambios de runtime ni BD)  
Owner direction: `lf_eventos #19834`  
Seguimiento: issue #1434

## 1. Objetivo

Diseñar una sola puerta Supabase para el detector periódico de currentness sin secretos en GitHub Actions.

Arquitectura aprobada por el owner:

```text
GitHub Actions
  permissions:
    contents: read
    id-token: write
        |
        | GitHub OIDC exact identity
        v
Supabase Edge gateway
  action=read_snapshot
      -> read-model mínimo de inventory
      -> Management API Edge Functions: Read
         usando scoped PAT almacenado en Supabase
  action=write_observation
      -> writer repetible de INV-9.1
      -> solo currentness + snapshot
```

GitHub NO recibe:
- `service_role`;
- contraseña Postgres;
- PAT de Supabase;
- credencial de escritura de inventario.

## 2. Identidad OIDC

La puerta no define un modelo OIDC distinto. Debe reutilizar el contrato exacto ya usado por
`supabase/functions/lf-profiles-governance-caller-v1/index.ts` (R14):

- issuer: `https://token.actions.githubusercontent.com`;
- algoritmo: `RS256`;
- JWKS del issuer;
- repository exacto: `cristhianlujan/claude-persona-lf-patch`;
- repository_id exacto: `1244397752`;
- ref exacta: `refs/heads/main`;
- run_id presente;
- workflow_sha SHA-1 de 40 hex;
- audience propia de la puerta;
- workflow/job_workflow_ref exacto del workflow fijo.

Workflow canónico propuesto:
`.github/workflows/lf-external-currentness-detector.yml`.

Audience propuesta:
`lf-external-currentness-gateway-v1`.

Regla de implementación para 9.2:
- no inventar una segunda semántica de validación;
- los tests de claims positivos/negativos deben reutilizar los mismos fixtures/reglas del caller;
- cualquier extracción a helper compartido debe preservar exactamente issuer/audience/repository/ref/workflow/run identity y códigos de rechazo equivalentes.

## 3. Acción `read_snapshot`

### Request lógico

```json
{
  "action": "read_snapshot",
  "request_id": "<uuid-or-run-scoped-id>",
  "observed_main_sha": "<40-hex>",
  "scope_policy_sha256": "<64-hex>"
}
```

El SHA de main no se confía ciegamente: debe coincidir con la identidad/ejecución que presenta GitHub y con el reporte posterior.

### Response lógico

```json
{
  "schema_version": "LF_EXTERNAL_CURRENTNESS_GATEWAY_SNAPSHOT_V1",
  "request_id": "...",
  "project_ref": "mhwmirqcgxxukpctffuv",
  "captured_at": "...",
  "repo_inventory": [
    {
      "object_ref": "repo://...",
      "active": true,
      "git_blob": "...",
      "source_version": null,
      "definition_sha256": null,
      "currentness": "CURRENT",
      "observed_at": "...",
      "observed_main_sha": "...",
      "source_traceability_state": null
    }
  ],
  "edge_inventory": [
    {
      "object_ref": "edge://...",
      "active": true,
      "git_blob": null,
      "source_version": "7",
      "definition_sha256": "...",
      "currentness": "CURRENT",
      "observed_at": "...",
      "observed_main_sha": "...",
      "source_traceability_state": "SOURCE_PRESENT"
    }
  ],
  "edge_runtime": [
    {
      "slug": "...",
      "version": 7,
      "ezbr_sha256": "...",
      "verify_jwt": false
    }
  ]
}
```

Read-model mínimo autorizado:
- `object_ref`;
- `active`;
- `metadata.git_blob` expuesto como `git_blob`;
- `source_version`;
- `definition_sha256`;
- `currentness`;
- `observed_at`;
- `observed_main_sha`;
- `source_traceability_state`.

No expone metadata completa, tags, dependencias, payloads funcionales ni datos de negocio.

## 4. Credencial Edge

`read_snapshot` obtiene runtime Edge mediante Management API.

Contrato de credencial:
- scoped PAT;
- un solo proyecto: `LF_SUPABASE_SANDBOX`;
- permiso: `Edge Functions: Read`;
- guardado en Supabase Vault/secrets;
- NO guardado en GitHub.

La disponibilidad del scoped PAT NO se asume. Debe verificarse en 9.3.

Si no está disponible:
`BLOCK_INV_9_3_AND_INV_9_4`.

Classic PAT:
`PROHIBITED`.

## 5. Acción `write_observation`

### Request lógico

```json
{
  "action": "write_observation",
  "report": {
    "schema_version": "LF_EXTERNAL_CURRENTNESS_REPORT_V1",
    "observed_main_sha": "<40-hex>",
    "detector_version": "<detector blob/version>",
    "scope_policy_hash": "<64-hex>",
    "input_digest_contract": "SHA256_CANONICAL_JSON_V1",
    "input_sha256": {
      "git_tree": "<64-hex>",
      "repo_inventory": "<64-hex>",
      "edge_runtime": "<64-hex>",
      "edge_inventory": "<64-hex>",
      "scope_policy": "<64-hex>"
    },
    "repository": { "...": "existing detector output" },
    "edge": { "...": "existing detector output" }
  }
}
```

La puerta NO recalcula el detector. Valida y entrega el reporte a la función DB de INV-9.1.

## 6. Boundary de escritura de INV-9.1

La función DB de 9.1 puede modificar únicamente, sobre objetos ya existentes:

- `currentness`;
- `currentness_source`;
- `observed_at`;
- `observed_main_sha`;
- `source_traceability_state` para `edge://`;
- `updated_at` como timestamp técnico.

Además inserta/retorna un registro en `inventory.snapshots`.

Fuera de alcance del writer:
- NO insertar objetos NEW;
- NO borrar objetos;
- NO cambiar `active`;
- NO cambiar `metadata.git_blob`;
- NO cambiar `source_version`;
- NO cambiar `definition_sha256`;
- NO tocar dependencias.

Esto preserva la separación:
- detector = observa drift;
- writer = persiste esa observación;
- una reconciliación/versionado posterior cambia la baseline del objeto cuando corresponda.

## 7. Idempotencia

La identidad de una observación queda definida por:

```text
observed_main_sha
+ detector_version
+ scope_policy_hash
+ input_sha256.git_tree
+ input_sha256.repo_inventory
+ input_sha256.edge_runtime
+ input_sha256.edge_inventory
+ input_sha256.scope_policy
```

La función de 9.1 debe generar un `snapshot_code` determinista a partir de esa identidad.

`inventory.snapshots.snapshot_code` ya es UNIQUE.

Reaplicar exactamente la misma observación:
- no crea un segundo snapshot;
- no cambia valores si ya coinciden;
- devuelve el snapshot existente;
- produce el mismo readback material.

## 8. Validaciones fail-closed

`write_observation` rechaza:

- `tree_truncated=true`;
- `pass_unknown_currentness=false`;
- cualquier registro con state `UNKNOWN`;
- schema_version no esperado;
- digest contract distinto de `SHA256_CANONICAL_JSON_V1`;
- hash faltante/malformado;
- `observed_main_sha` distinto de la identidad de ejecución;
- `scope_policy_hash` distinto del policy esperado;
- objetos fuera de `repo://` o `edge://`;
- intento de persistir NEW como objeto;
- clasificación de un object_ref que no existe cuando no es NEW;
- duplicados contradictorios del mismo object_ref/slug.

## 9. Errores de la puerta

Códigos mínimos:

```text
OIDC_BEARER_MISSING
OIDC_TOKEN_INVALID
OIDC_REPOSITORY_MISMATCH
OIDC_REF_MISMATCH
OIDC_WORKFLOW_IDENTITY_MISMATCH
OIDC_RUN_IDENTITY_INCOMPLETE
ACTION_NOT_ALLOWED

EDGE_READ_CREDENTIAL_MISSING
EDGE_READ_CREDENTIAL_FORBIDDEN
EDGE_RUNTIME_FETCH_FAILED

SNAPSHOT_REQUEST_INVALID
REPORT_SCHEMA_INVALID
REPORT_DIGEST_INVALID
REPORT_MAIN_SHA_MISMATCH
REPORT_SCOPE_POLICY_MISMATCH
REPORT_TREE_TRUNCATED
REPORT_UNKNOWN_CURRENTNESS
REPORT_OBJECT_OUT_OF_SCOPE
REPORT_NEW_OBJECT_WRITE_FORBIDDEN

OBSERVATION_ALREADY_APPLIED
OBSERVATION_APPLIED
```

No se registran tokens ni headers de autorización en logs.

## 10. Secuencia de INV-9

```text
9.0 D  diseño (este documento)
9.1 E  funciones DB read-model + writer repetible
9.2 R  Edge gateway + tests OIDC + deploy
9.3 A  scoped PAT en Supabase, disponibilidad verificada
9.4 R  workflow fijo main/push/6h/manual
9.5 C  cierre
```

Nota:
9.2 puede desplegar la puerta antes de 9.3, pero `read_snapshot` debe fallar cerrado con
`EDGE_READ_CREDENTIAL_MISSING` hasta que exista la credencial scoped.

## 11. Relación con INV-9.E0

La TTL de 7 horas sigue siendo red de seguridad.

No sustituye:
- detector post-deploy;
- workflow periódico;
- persistencia de observaciones.

Toda unidad R sigue obligada a reportar estado recalculado + `observed_at` antes de cerrar.
