# X16 — brecha de controles para runtimes productivos

Estado: documento de análisis para Train. X16 permanece en BACKLOG. Este inventario no modifica registros, activa checks ni toca la base.

Fuente: `main` en `d9b41e79344d7c53a81fe19e0783a642aa50068c`. Se enumeraron las 18 carpetas de `supabase/functions/` y se ejecutó `classify(["supabase/functions/<nombre>/index.ts"])` con los registros de ese commit. La única función de prueba identificada por nombre es `get-perfil-lf-runtime-protocol-public-test`; las otras 17 se consideran productivas para este inventario.

| Función | Uso | `classify()` actual | Controles actuales | Control de regresión existente que conviene evaluar |
|---|---|---|---|---|
| `get-perfil-lf-runtime-protocol` | Productiva | `DEEP_SHARED_KNOWN` | — | `PROFILE_RUNTIME_V3`, por servir el protocolo de runtime de perfiles |
| `get-perfil-lf-runtime-protocol-public-test` | Prueba | `DEEP_SHARED_KNOWN` | — | Ninguno; decisión 2 mantiene el runtime de prueba sin control |
| `input-governance-agent-v1` | Productiva | `DEEP_SHARED_KNOWN` | — | Sin regresión existente específica para Edge Function; `INPUT_GOVERNANCE_MIGRATION_PARITY` cubre material de paridad/migración, no esta función |
| `input-governance-curator-v1` | Productiva | `DEEP_SHARED_KNOWN` | — | Sin regresión existente específica para Edge Function; revisar si `LF_CONTRACT_CORE` prueba su contrato antes de proponer una asignación |
| `input-governance-validator-v1` | Productiva | `DEEP_SHARED_KNOWN` | — | Sin regresión existente específica para Edge Function; revisar si `LF_CONTRACT_CORE` prueba su contrato antes de proponer una asignación |
| `lf-architecture-alert-sink-v4` | Productiva | `DEEP_SHARED_KNOWN` | — | Sin control de regresión existente con correspondencia demostrada |
| `lf-external-currentness-gateway-v1` | Productiva | `DEEP_SHARED_KNOWN` | — | Sin control de regresión existente con correspondencia demostrada |
| `lf-p0-exact-head-evidence-broker-v2` | Productiva | `SPECIALIZED_REQUIRED` | `P0_EXACT_HEAD_EXTERNAL` | `P0_EXACT_HEAD_EXTERNAL` ya aplica; validar su cobertura de regresión en el carrier actual |
| `lf-p0-human-review-v42-materialize-v1` | Productiva | `DEEP_SHARED_KNOWN` | — | Sin control existente que cubra materialización de esta Edge Function |
| `lf-p0-human-review-web-v1` | Productiva | `DEEP_SHARED_KNOWN` | — | Sin control existente que cubra este runtime web; `P0_VISUAL_RUNTIME` apunta a otra superficie |
| `lf-profile-creator-governance-caller-v1` | Productiva | `DEEP_SHARED_KNOWN` | — | `PROFILE_RUNTIME_V3`, sujeto a confirmar que el carrier valide este caller |
| `lf-profiles-governance-caller-v1` | Productiva | `DEEP_SHARED_KNOWN` | — | `PROFILE_RUNTIME_V3`, sujeto a confirmar que el carrier valide este caller |
| `lf-runtime-independent-readback-v1` | Productiva | `DEEP_SHARED_KNOWN` | — | Sin regresión existente específica para Edge Function; el control de readback actual solo está ligado a `supabase/config.toml` |
| `run-creacion-perfil-lf` | Productiva | `DEEP_SHARED_KNOWN` | — | `PROFILE_RUNTIME_V3`, por operar sobre runtime de perfiles |
| `run-formalizacion-perfil-lf` | Productiva | `DEEP_SHARED_KNOWN` | — | `PROFILE_RUNTIME_V3`, por operar sobre runtime de perfiles |
| `run-github-readback-perfil-lf` | Productiva | `DEEP_SHARED_KNOWN` | — | Sin regresión existente específica para Edge Function |
| `run-github-write-perfil-lf` | Productiva | `DEEP_SHARED_KNOWN` | — | Sin regresión existente específica para Edge Function; no asignar controles de migración sin cobertura demostrada |
| `story-agent-evidence-verifier-v1` | Productiva | `DEEP_SHARED_KNOWN` | — | Sin regresión existente específica para Edge Function; revisar si `LF_CONTRACT_CORE` valida su contrato antes de proponer una asignación |

## Lectura del inventario

- El control existente `PROFILE_RUNTIME_V3` corre por `VALIDATE_LF_PACKS` y hoy se activa para `services/profile_runtime_api/`, directorios de runtime de perfiles y `profiles/`; sus matchers actuales no incluyen `supabase/functions/`.
- `P0_EXACT_HEAD_EXTERNAL` es el único control observado en una función productiva y está acotado al broker exact-head.
- No hay una regresión existente que cubra en conjunto las funciones de gobernanza, currentness, alertas, readback y escritura. Donde la tabla dice “sin regresión específica”, la propuesta es registrar esa brecha para decisión del owner; no ampliar a ciegas un control cuyo carrier no pruebe el runtime.
- `DB_CANDIDATE_APPLY_ROLLBACK` no se propone para funciones: su carrier es `LF_DB_REGRESSION` y el control se define para rutas de migración.

El siguiente paso requiere decisión de Cristhian sobre cobertura funcional de `PROFILE_RUNTIME_V3` y sobre qué contrato de regresión agregar para las Edge Functions productivas restantes. Esta nota no hace esa asignación en los registros.
