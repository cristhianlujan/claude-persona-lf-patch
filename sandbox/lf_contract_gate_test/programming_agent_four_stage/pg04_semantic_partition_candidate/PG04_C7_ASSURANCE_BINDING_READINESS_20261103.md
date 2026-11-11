# PG-04_C7 — Enlace con INDEPENDENT_ASSURANCE (corte 2026-11-03)

## Resultado

`GENERIC_ASSURANCE_CURRENT / PG04_SUBJECT_VERIFIED_COUNT=0 / SOURCE_ONLY_REQUEST_PREPARED / NO_GO_REVIEW_EXECUTION`.

Este documento registra la verificación del **repositorio principal** y de **Supabase (SELECT solamente)**. No se creó operación, juez, resolver, tabla ni writer.

### 1. Autoridad existente comprobada

- Migración vigente de diseño: `supabase/migrations/20261009034828_independent_assurance_generic_subject_v3.sql` (Git blob `e2661530e48ccd1b6776b4946d315f4d20cef3ed`).
- Función canónica `public.lf_independent_review_begin_v3`: exige `subject_type`, `subject_ref`, SHA256 del sujeto, SHA del source HEAD, `subject_receipt_id` UUID, `producer_execution_id`, `reviewer_execution_id` distinto, `review_required` y dimensiones. Comprueba que el recibo exista en `private.lf_evidence_ledger_v1`, sea `VERIFIED`, y coincida exactamente en tipo, ref, digest y HEAD; luego utiliza el circuito de reserva gobernado de la operación.
- Lectura SQL actual a `public.lf_capability_current` + `public.lf_capability_version_registry`: `INDEPENDENT_ASSURANCE` versión **2.0.1**, `RELEASED`, modo **CONTRACT_DRIVEN_ANY_SUBJECT**, `subject_type_whitelist=false`.
- Lectura SQL a `private.lf_evidence_ledger_v1` para `subject_type='PG04_SOLUTION_PARTITION_CANDIDATE'`, `capability_code='EVIDENCE_LEDGER'`, `verification_state='VERIFIED'`: **0 sujetos**.
- Lectura SQL actual checkpoints: `PG01_C6`, `PG03_C3`, `PG03_C9`, `PG04_C2` y `PG04_C7` en `PENDING`.
- PR #3528 fue abierto **draft** contra `main`. PASE run #41709508310 en HEAD previo `bf95dc30bc400890971a0bcb824b6de13aff5e98`: `SUCCESS`. Eso valida la ruta PASE, **no** ejecución integral de las pruebas Python ni el revisor semántico.

### 2. Adaptación mínima ejecutada en código (sin segunda revisión)

`tools/pg04_independent_review_request_v1.py` ahora declara:
- `subject_type='PG04_SOLUTION_PARTITION_CANDIDATE'`;
- `subject_ref='PG04_SOLUTION_PARTITION_CANDIDATE/'+candidate_sha256`;
- `subject_sha256` sobre el sobre íntegro y `source_head_sha` del manifiesto;
- `subject_receipt_id=None`: **no se inventa UUID ni recibo de ledger**;
- `first_runtime_blocker='PG04_VERIFIED_SUBJECT_RECEIPT_MISSING'`;
- obligaciones de recibo VERIFIED, A9/PG03 readback, reviewer independiente, dispatch gobernado.

La salida mantiene `CANDIDATE_NOT_ADMITTED`, `source_readback_verified=false`, `ledger_receipt_verified=false`, `semantic_judge_executed=false`, `review_execution_allowed=false`, `handoff_allowed=false`, `production_authority=false`. El manifold `sources` tiene digest y referencias suministrados por caller, pero **no autentica** esas referencias; su hash solo inmoviliza bytes para la comparación posterior.

En `tests/test_pg04_independent_review_request_v1.py` se añadió regresión para comprobar que el recibo es explícitamente `None` y que no hay ejecución.

### 3. Separación de jueces

La sonda `pg04_partition_admission_probe_v1.py` inspecciona forma, cobertura y vínculos deterministas.
El generador `pg04_semantic_partition_candidate_v1.py` particiona usando `outcome_id` y cohesión suministrados; **no valida semánticamente la verdad del outcome**.
El revisor semántico independiente de LF (capability genérica `INDEPENDENT_ASSURANCE`) tendría que comparar A9 real contra cada solución y sus componentes; no puede reemplazarse con un PASS inventado, un fixture, ni el propio generador.

### 4. Camino exacto de desbloqueo

1. Obtener A9 real CURRENT y PG01_C6 `ACCEPT` gobernado con readback, luego estrategia PG03 y C9 autenticados.
2. Generar una partición PG04 con sujeto congelado y SHA exacto; obtener `EVIDENCE_LEDGER` **SOURCE_SNAPSHOT VERIFIED** sobre ese sujeto mediante escritor/resolutor autorizados, nunca SQL de prueba.
3. Resolver el revisor independiente y ejecutar la operación `REVISION_INDEPENDIENTE_ESTRATEGIA_LF` mediante la capacidad genérica y el orquestador permitido.
4. Emitir y leer de vuelta veredicto auténtico ligado al mismo SHA y origen; comprobar C7 cobertura real (cero huérfanos). Solo entonces evaluar admisión y cierre checkpoint oficial.

No se llamó `lf_independent_review_begin_v3`, `fn_lf_operation_reserve_execution_v1` ni se modificó Supabase.

**Dictamen:** `PG04_C7_REVIEW_REQUEST_SOURCE_READY / GENERIC_ASSURANCE_EXISTS / VERIFIED_SUBJECT_MISSING / REVIEW_NOT_EXECUTED`.
