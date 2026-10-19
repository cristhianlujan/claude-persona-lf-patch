# RW1-01_C1 — Atestación material para cierre gobernado

**Sujeto:** `LF_ROUTER_ARCHITECTURE_WAVE_V1/RW1-01/RW1-01_C1`, work item `1127`, checkpoint `1607`. **Alcance:** C1 (fuentes e identidad), exclusivamente. Se reutiliza A16Q_C1; no repetir el inventario.

## Fuentes inspeccionadas realmente

| Componente | Lectura / identidad exacta |
|---|---|
| OLA registrada | Evento `public.lf_eventos/21263` y `engineering_plan_units/RW1-01`; seis unidades, dieciocho checkpoints de la ola |
| Contrato de entrada C1 | `programacion.fn_engineering_checkpoint_action_spec_v3(...,RW1-01_C1)`: `READY`, `READBACK_ONCE`, `EXPLICIT_ACTION_SPEC`, tres consultas |
| Preparación | `programacion.fn_engineering_checkpoint_execution_readiness_v1(...,RW1-01_C1)`: `READY`, sin razones, source `CURRENT`, gates READY |
| Preflight material | `programacion.fn_engineering_checkpoint_source_query_preflight_v1(...,RW1-01_C1)`: `PASS`, `query_count=3`, `passed=3`, `failed=0` |
| Fuente actual A16Q | `A16Q_C1=DONE` con evidence_ref exacto, sin consumir estado de A16Q_C2/C3 |
| EKB | Cinco entradas existentes con causa y prevención material (ver documento de lectura) |
| Fuente GitHub vigente | [PR #2876](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2876) MERGED, `merge_sha=edf61fe3a503f49b6ddcada3232819633efbbace` |
| C1 necesidades | `docs/programming-agent/router_wave/RW1_01_C1_NEEDS_SOURCES_AND_BIASES_V1.md` blob `89aeae9e3116ebee9c2f547c2f41c4f2ba23c69d`; 12 necesidades N01–N12, fuentes S01–S10, sesgos B01–B10 |
| C1 readback | `docs/programming-agent/router_wave/RW1_01_C1_SOURCE_READBACK_OBSERVED_20261017.md` blob `709cb10280a811c2d0d81a4e6a0b11772c03335b` |

La validación **fue real, no inferida del título**. La comprobación no atribuye efecto autorizado a ACT-0001 ni acredita entregas a consumidores reales.

## Aserción y paso de cierre

- Con `README`, PR o source pack **no basta**. El cierre se efectuará mediante `programacion.fn_engineering_checkpoint_transition_v1(...,'DONE',evidence_ref,p_actor,p_detail)` **dentro de Migration Merge Train**, solo si la propia migración revalida `READY`, tres queries `PASS`, EKB y A16Q.
- La migración comprueba posterior `RW1-01_C1=DONE`, `RW1-01_C2/C3=PENDING`, unidad `IN_PROGRESS`, C1 único cerrado en la ola. Si alguno falla, transacción completa se revierte.
- No se solicita ni infiere promoción GOLDEN, cambio de runtime/producción, CI/PASE desactivados, ni reparación ad-hoc del Router.
- El corpus de 30 casos y sus revisiones son evidencia preparatoria **C2**, no se reclama C2 PASS.

**Riesgo residual:** el guard de C1 es READ-ONLY y su confirmación de fuente/recibos externos es una conciliación del agente y de GitHub, no un consumidor E2E. Los próximos checkpoints C2/C3 conservan la obligación de verificación independiente.
