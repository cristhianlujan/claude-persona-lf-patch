# RW1-03_C1 — Baseline de contratos, consumidores, permisos y EKB afectados

**Plan:** `LF_ROUTER_ARCHITECTURE_WAVE_V1`  
**Unidad:** `RW1-03` — Contrato y estrategia de transición  
**Checkpoint:** `RW1-03_C1`  
**Naturaleza:** fuente/autoridad de solo lectura. No define todavía el ABI final, no modifica Router runtime, no cambia ACL, no activa perfiles/adapters y no autoriza efectos.

## 1. Dependencia arquitectónica ya resuelta

RW1-02 cerró 3/3 y el veredicto independiente V2 seleccionó:

`A_MIN_ROUTER_SEMANTIC_SPECIALIST`

Contrato estructural heredado para RW1-03:

- ACT-0001 conserva **discovery, derivation y currentness**.
- El especialista semántico es externo al Router y solo puede normalizar intención, negaciones, exclusiones, condiciones, contexto y ambigüedad.
- El especialista **no puede descubrir workers, rutear ni autorizar efectos**.
- La autoridad de efecto permanece en operación/consumidor y sus guards.
- `target_hint` no adquiere autoridad.
- Merge Train conserva ruta técnica separada.
- Read-only puede continuar cuando el write correspondiente está bloqueado.
- Estado stale/currentness falla cerrado.

Fuente ganadora: `RW1_02_C3_INDEPENDENT_VERDICT_V2.json` (blob `623c9926d745bf0670156fe1b96d5729f0e4900b`), sustentada en `RW1_02_C2_ARCHITECTURE_COMPETITION_V2.json` (blob `cf22d9889eb008dc7afcf64dd1b3712b9536ec98`).

## 2. Freeze de fuente vigente

Main congelado para C1: `e02a9836f0ea51214f9f9583fe2281367002f3ff`.

Fuentes reutilizadas, sin duplicar A16Q:

| Fuente | Blob / identidad | Uso en C1 |
|---|---|---|
| `LF_ROUTER_ARCHITECTURE_WAVE_V1.md` | `4bb64d568c3f005cf454fb223b4a5ed699c34504` | alcance y exit criterion de RW1-03 |
| `RW1_02_C3_INDEPENDENT_VERDICT_V2.json` | `623c9926d745bf0670156fe1b96d5729f0e4900b` | arquitectura ganadora |
| `RW1_02_C2_ARCHITECTURE_COMPETITION_V2.json` | `cf22d9889eb008dc7afcf64dd1b3712b9536ec98` | invariantes del diseño ganador |
| `ANALYSIS_A16Q_C1_ROUTER_CONSUMER_INVENTORY_V1.md` | `28e020ba05721892524bfc7971cd7c0f3a8f9878` | inventario reusable de consumidores/autoridad |
| `ANALYSIS_A16Q_C2_CONSUMER_TRACE_BASELINE_V1.md` | `72b4e5977c96162ab60c5d76a1b070bd5d70b3eb` | brechas de traza E2E y binding |
| `PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF.md` | `06d8905db56f04bf8557ccb0db556a25f704d015` | contrato vigente de consumo del Router |

Readback DB actual:

- `public.lf_router_resolve_v1(...)`: md5 `d45f5bddb693791b6459bbe3acfd4ed3`.
- `public.lf_router_intent_handoff_v1(text,jsonb,text)`: md5 `540bc1b60caf2e3f9d81461f99c509ef`.
- `programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text)`: md5 `72e153a7fbfe7b10a8c9ae694a61b334`.
- `lf_router_action_registry`: 35 rutas ACTIVE = 26 write + 9 non-write.

## 3. Superficies estrictamente afectadas

C1 identifica **cinco grupos**. Que una superficie esté afectada no significa que C2 deba modificarla; C2 decidirá ABI y transición mínima.

### S1 — Entrada y derivación de ACT-0001

- `public.lf_router_resolve_v1(text,text,text,text,text)`
- `public.lf_router_action_registry`
- `public.v_lf_fuente_operativa_busqueda`
- currentness/target identity y candidate discovery

Responsabilidad que debe conservarse: discovery + derivation + currentness. No trasladar autoridad de efecto al especialista.

### S2 — Handoff semántico

Existe ya `public.lf_router_intent_handoff_v1` con envelope `LF_ROUTER_INTENT_HANDOFF_V1`.

Campos actuales relevantes: solicitud literal, SHA-256, reference kind, candidate subjects, positive/excluded refs, allowed/forbidden scope, binding state, semantic consumer receipt, executor binding state y `downstream_execution_allowed=false`.

**Implicación:** RW1-03_C2 debe evaluar primero evolución/reuso de este handoff antes de crear otra abstracción compartida. C1 no autoriza modificarlo ni convertirlo en segundo Router.

### S3 — Autoridad de efecto y guards

Deben permanecer fuera del especialista:

- `ROUTER_DOWNSTREAM_AUTHORITY`
- `OPERATION_EFFECT_GUARD`
- `OPERATION_MATERIALIZATION_GUARD`
- contratos/pasos/policies de la operación resuelta

La normalización semántica nunca equivale a permiso de escritura, selección de executor ni recepción de autoridad operativa.

### S4 — Consumidores

Consumidores/receptores que C2/C5 deben mantener compatibles o migrar explícitamente:

1. Contrato de caller Claude/GPT: `PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF.md`.
2. `sandbox/lf_contract_gate_test/profile_execution_runtime/github_actions_batch_queue_worker.py`.
3. `services/profile_runtime_api/profile_runtime_api/app.py` y `engine.py`.
4. Input Governance solo cuando un adapter aplicable lo exige: `fn_lf_router_input_governance_resolve_v1`.
5. Canonical route guard / operación resuelta antes del primer efecto.

A16Q ya demostró que código consumidor, runtime receipt y operación canónica no deben confundirse. RW1-03 no repite ese inventario.

### S5 — Ruta técnica de DB / Train

`ACTUALIZACION_DB_LF → MIGRATION_VIA_MERGE_TRAIN` permanece una ruta técnica separada.

El especialista semántico:
- no sustituye Merge Train;
- no puede fabricar autorización para Train;
- no debe introducir dependencia circular donde Train requiera una autoridad que solo pueda nacer después del propio apply.

## 4. Fronteras de permisos verificadas

| Superficie | ACL/seguridad actual | Regla para C2 |
|---|---|---|
| `lf_router_resolve_v1` | invoker; EXECUTE: postgres, service_role, supabase_read_only_user | preservar separación entre inspección y efecto |
| `lf_router_intent_handoff_v1` | invoker; EXECUTE actual incluye PUBLIC/anon/authenticated/service_role | **superficie sensible**: C2 debe decidir compatibilidad/ACL explícita antes de cualquier capacidad nueva |
| `fn_lf_router_input_governance_resolve_v1` | SECURITY DEFINER; EXECUTE: postgres + service_role | no ampliar ACL por conveniencia |

La selección A no concede privilegios al futuro especialista. Cualquier identidad/runtime futuro debe recibir solo capacidad de normalización y cero autoridad de efecto.

## 5. EKB aplicable y current

Readback C1 encontró **12 entradas activas** dentro del conjunto Router + consumer authority:

- `LF-ROUTER-ACT0001-LEXICAL-MISROUTE-20261015-001`
- `LF-ROUTER-ACT0001-PREWRITE-INTENT-GATE-20261015-002`
- `LF-ROUTER-ACT0001-UNSTRUCTURED-MUTATION-FALSE-READY-20261017-002`
- `LF-ROUTER-ACT0001-TYPED-TARGET-AUTHORITY-BYPASS-20261017-003`
- `LF-ROUTER-ACT0001-CROSSROLE-LEXICAL-20261016-005`
- `LF-ROUTER-ACT0001-SCREEN-SHORTCIRCUIT-20261016-003`
- `LF-ROUTER-ACT0001-LEXICAL-ARTIFACT-MISIDENTITY-20261017-001`
- `CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL`
- `ENGINEERING-FOUR-CAPABILITY-ROUTER-001`
- `ENGINEERING-CONSUMER-PROBE-WRITE-MISCLASSIFICATION-001`
- `POST-PASE-CONSUMER-CANONICAL-BINDING-001`
- `ENGINEERING-REPOSITORY-CAPABILITY-CONSUMER-ASSERTION-001`

Se reutilizan como restricciones/falsificadores, no como recetas de implementación.

## 6. Superficies explícitamente fuera de C1

C1 **no**:
- define el ABI final del especialista;
- crea operación nueva;
- cambia `lf_router_resolve_v1`;
- cambia `lf_router_intent_handoff_v1`;
- cambia ACLs;
- habilita perfiles/adapters/runtime;
- cambia Merge Train;
- modifica `EJECUCION_PERFIL_LF`;
- afirma Router runtime PASS;
- afirma E2E PASS;
- toca RW1-04..06.

## 7. Contrato de salida para RW1-03_C2

C2 puede comenzar únicamente sobre este mapa y debe producir, como mínimo:

1. ABI versionado Router ↔ especialista ↔ responsable.
2. Contexto mínimo íntegro: literal + hash + targets/exclusions + condiciones + currentness.
3. Regla de aclaración material, sin preguntas redundantes.
4. Respuesta del especialista sin capacidad de route/effect.
5. Binding explícito de authority antes del primer efecto.
6. Compatibilidad/migración de consumidores existentes.
7. Plan de corte/reversión sin doble Router ni circularidad de Train.
8. Negativos para stale source, scope widening, forged target, bypass de caller y ACL incorrecta.

## 8. Criterio de cierre de C1

C1 puede marcarse DONE solo si:

- RW1-02 está 3/3 DONE y selección A está congelada.
- Main/blobs y md5 DB anteriores son current al ejecutar el cierre.
- A16Q C1/C2 se reutilizan sin duplicación.
- Los 5 grupos afectados quedan explícitos.
- Las 3 fronteras de permisos quedan verificadas.
- Las 12 entradas EKB existen y están activas.
- El evento del plan sigue con `acceptance_declared=false`.
- No hubo mutación de Router runtime, ACL, perfiles/adapters, operación ni producción.

**Resultado C1:** mapa de autoridad y superficies para que C2 diseñe el contrato objetivo sin ampliar Router ni inventar autoridad.
