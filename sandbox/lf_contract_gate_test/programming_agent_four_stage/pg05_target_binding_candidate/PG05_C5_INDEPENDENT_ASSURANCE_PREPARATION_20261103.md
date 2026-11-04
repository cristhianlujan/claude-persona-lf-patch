# PG-05_C5 — Solicitud candidata de revisión independiente (2026-11-03)

## Objetivo

Preparar el aseguramiento independiente para PG-05 (target, write-scope, locks y bloqueos por solución) **sin crear un segundo juez** ni modificar el mecanismo canónico `INDEPENDENT_ASSURANCE`.

Checkpoint canónico PG-05_C5: “Aseguramiento independiente”. Los checkpoints C1–C4 se mantienen independientes en sus obligaciones: su código candidato no equivale a admisión o pruebas ejecutadas.

## Implementación

`tools/pg05_c5_independent_assurance_request_v1.py` agrega:

`prepare_pg05_assurance_request(pg04_exit, pg05_c1, pg05_c2, pg05_c3, pg05_c4, source_manifest, producer_execution_id)`

Consume cinco sobres, con SHA exacto verificado y vínculos cruzados entre ellos:
- `PG04_TO_PG05_EXIT_CANDIDATE_V1`;
- `PG05_C1_TARGET_BINDING_PREFLIGHT_CANDIDATE_V1`;
- `PG05_C2_WRITE_SCOPE_RESOLUTION_CANDIDATE_V1`;
- `PG05_C3_CONFLICT_LOCK_PLAN_CANDIDATE_V1`;
- `PG05_C4_WRITE_BOUNDARY_DIAGNOSTIC_CANDIDATE_V1`.

Requiere que todos sigan en estado fuente no admitido, sin branch creado, sin locks adquiridos, sin despacho, sin permisos de escritura y sin autoridad productiva.

Confronta la lista de `solution_id` de PG-04 contra las listas C1, C2, C3 y C4. Exige manifiesto explícito con `source_head_sha` de 40 hexadecimales y pares `ref`/`sha256` de cada sobre. Ese manifiesto **congela declaraciones** suministradas por el caller, pero no autentica currentness ni autoría.

### Sujeto de la revisión

El preflight genera `PG05_C5_ASSURANCE_SUBJECT_CANDIDATE_V1`, cuyo digest SHA256 liga:
- digest PG04 y C1–C4;
- digest del manifiesto de origen;
- soluciones completas;
- soluciones con hallazgos `BLOCKED_SCOPE_VIOLATION`;
- soluciones sin hallazgos visibles, expresamente **no admitidas**.

La solicitud `PG05_C5_INDEPENDENT_REVIEW_REQUEST_CANDIDATE_V1` incorpora el sujeto íntegro, su digest, el HEAD de origen, la identidad del productor y la intención de usar `INDEPENDENT_ASSURANCE` con la operación existente `REVISION_INDEPENDIENTE_ESTRATEGIA_LF`.

### Aserciones que debe revisar la capacidad independiente

1. Destino exacto y readback CURRENT de repo/base SHA.
2. Admisión auténtica de PG-04 y coherencia del paquete.
3. Alcance L3 por solución y admisión canónica de rutas.
4. Solo lectura de contratos compartidos y seguridad de objetos DB.
5. Choques entre writers, dependencias y autoridad de locks reales.
6. Negativos de C4: escritura fuera de scope da BLOCK por solución.
7. No escalamiento de permisos por Changeset Governance.
8. Independencia del revisor y recibo VERIFIED del sujeto exacto.

### Bloqueadores y límites

El paquete no invoca `public.lf_independent_review_begin_v3`, no verifica `private.lf_evidence_ledger_v1`, no reserva operación ni inicia un revisor. **No permite** `subject_receipt_id` ficticio: lo deja `null`. El `reviewer_execution_id` también es `null`.

Flags invariantes: `ledger_subject_receipt_verified=false`, `source_readback_verified=false`, `independent_review_executed=false`, `review_execution_allowed=false`, `pg05_admitted=false`, `branch_creation_allowed=false`, `write_allowed=false`, `production_authority=false`, `handoff_allowed=false`.

La solicitud tiene `first_runtime_blocker=PG05_VERIFIED_SUBJECT_RECEIPT_MISSING` como **bloqueo de diseño**, no como comprobación SQL que identifique una fila faltante. Antes de ejecutar debe hacerse un readback real del ledger y comprobar admisión upstream y currentness. Incluso si se obtiene VERIFIED, C4 requiere resultados negativos realmente ejecutados y C3 locks reales.

**Estado:** `PG05_C5_REVIEW_REQUEST_SOURCE_READY / NO_AUTHENTIC_SUBJECT_RECEIPT / REVIEW_NOT_EXECUTED / OFFICIAL_PENDING`.

Por decisión del Owner, las pruebas Python y la calificación exact-HEAD están aplazadas. No escribir en Supabase, no tocar Análisis o main, no fusionar PR #3528 y no crear ramas de producto.
