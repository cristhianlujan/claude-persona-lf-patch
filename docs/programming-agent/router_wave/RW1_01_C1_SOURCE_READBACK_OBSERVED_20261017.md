# RW1-01_C1 — Lectura material de fuentes actuales (sin efecto)

**Plan:** `LF_ROUTER_ARCHITECTURE_WAVE_V1` · **Unidad:** RW1-01 · **Checkpoint:** RW1-01_C1.  
**Fecha:** 2026-10-17. **Ejecución:** 3 consultas SELECT efectivas a Supabase a través del conector read-only. **No** se invocó `fn_engineering_checkpoint_transition_v1`, ni se insertó un receipt en checkpoint, ni se hizo DDL/DML.

## Queries exactas obtenidas del source pack candidato

Fuente de las consultas: `supabase/migrations/20261017134500_lf_router_wave_rw101_c1_source_bind_v1.sql` en rama `wave/rw1-01-c1-evidence-source-20261017`. Se extrajo el objeto `v_pack`, clave `checkpoint_inputs.RW1-01_C1.inputs.queries`; no se cambiaron las consultas durante la ejecución.

| Query | Filas | Resultado real observado |
|---|---:|---|
| Q1 — Plan y checkpoint exacto | 1 | `plan_code=LF_ROUTER_ARCHITECTURE_WAVE_V1`; `unit_code=RW1-01`; `work_item_id=1127`; `RW1-01_C1=PENDING` |
| Q2 — Reuso de autoridad preexistente | 1 | `PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1/A16Q/A16Q_C1=DONE`; evidence_ref `docs/programming-agent/ANALYSIS_A16Q_C1_ROUTER_CONSUMER_INVENTORY_V1.md@9185fe6e09e0af79d0db145fe80bcc8d65173565#blob:28e020ba05721892524bfc7971cd7c0f3a8f9878` |
| Q3 — EKB consultado | 5 | Los cinco códigos declarados existían y cada fila tenía `causa_raiz` y `prevencion` no vacíos |

Los cinco códigos EKB leídos: `LF-ROUTER-ACT0001-LEXICAL-MISROUTE-20261015-001`; `LF-ROUTER-ACT0001-PREWRITE-INTENT-GATE-20261015-002`; `LF-ROUTER-ACT0001-UNSTRUCTURED-MUTATION-FALSE-READY-20261017-002`; `LF-ROUTER-ACT0001-TYPED-TARGET-AUTHORITY-BYPASS-20261017-003`; `CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL`.

## Conclusiones limitadas

1. Se pudo **reutilizar** A16Q_C1 sin repetir inventario ni declarar su C2/C3 finalizado.
2. Todas las fuentes DB del source pack C1 propuesto fueron **leídas materialmente** con resultado observable.
3. Esto no demuestra que el contrato haya sido **integrado** en `engineering_plan_units.unit_metadata`: en readback previo `action_specs_v1=false` y `source_pack_v2=false`. Tampoco atesta el SHA actual de los documentos GH como ejecutor externo.
4. No es una prueba del Router, de su consumidor ni una crítica independiente. Los requisitos originales y sesgos están en `RW1_01_C1_NEEDS_SOURCES_AND_BIASES_V1.md`.
5. Una lectura manual de fuente de C1 no satisface por sí sola `assertion_contract_sha256`, `assertion_receipt`, `source_currentness` ni la transición canónica.

**Estado del checkpoint:** `PENDING`. **Estado de ola:** `0/18 DONE`. Mantener sin cambios hasta CI/PASE/Train de bindings y evidencia de cierre válida.
