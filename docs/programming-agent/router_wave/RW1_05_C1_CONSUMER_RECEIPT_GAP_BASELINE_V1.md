# RW1-05_C1 — Baseline vigente de consumidores, contratos y receipts post-refactor

- **Plan:** `LF_ROUTER_ARCHITECTURE_WAVE_V1`
- **Unidad:** `RW1-05`
- **Checkpoint:** `RW1-05_C1`
- **Fuente Git congelada:** `8c37bd90639fa84cf1a9b7b2858ba780b08f92fb`
- **Ámbito:** consumidores realmente aplicables después de RW1-04; inventario diferencial respecto de A16Q_C2.
- **Naturaleza:** evidencia de solo lectura. Este documento **no** implementa T2/T3, no ejecuta perfiles, no activa runtime, no concede autoridad de efecto y no abre C2/C3.

## 1. Autoridad reutilizada, sin duplicar inventario

Se reutilizan como autoridad de diseño y baseline:

| Fuente | Git blob | Uso |
|---|---|---|
| `ANALYSIS_A16Q_C2_CONSUMER_TRACE_BASELINE_V1.md` | `72b4e5977c96162ab60c5d76a1b070bd5d70b3eb` | baseline histórico Router→consumer y traza de 13 campos |
| `a16q_c2_router_consumer_trace.py` | `38ee6371627202a9fc36f17bdbe08a734fdedadd` | contrato fail-closed de evidencia real |
| `RW1_02_C2_ARCHITECTURE_COMPETITION_V2.json` | `cf22d9889eb008dc7afcf64dd1b3712b9536ec98` | arquitectura ganadora y definición del semantic specialist |
| `RW1_03_C2_SEMANTIC_ABI_TRANSITION_V1.json` | `bfd571d5e7c7d1d80c5ed39414a822b4096c20d6` | ABI, autoridad, aclaración y fases T0–T4 |
| RW1-04 implementación V2 | `14619e0a883d42db1e9b25f471e85a5800f970d7` | handoff V2 + resume validator instalados en T1 |

RW1-04 terminó T1: V2 y resume existen y se dual-emiten junto a V1, pero el runtime semántico permanece shadow/disabled.

## 2. Fuente actual exacta

Readback en la fuente congelada:

- `public.lf_router_resolve_v1` md5: `8cffdd7403c0ae40d5db19890ea4f944`
- `public.lf_router_intent_handoff_v1` md5: `540bc1b60caf2e3f9d81461f99c509ef`
- `public.lf_router_intent_handoff_v2` md5: `e6c5df658f322e0c67ee7a2bb5972410`
- `public.lf_router_semantic_resume_validate_v1` md5: `4dc0dad03d7259009583e2f77f5930fb`
- rutas Router ACTIVE: **35**
- ejecuciones `EJECUCION_PERFIL_LF` creadas después del cierre de RW1-04: **0**
- ejecuciones `EJECUCION_PERFIL_LF` PASS después del cierre de RW1-04: **0**
- ejecuciones actuales de `ACTUALIZACION_DB_LF` COMPLETED con `router_authority_receipt` + `closure_evidence` durante 2026-10-21: **10**

## 3. Consumidores realmente aplicables

| Superficie | Estado actual | Evidencia | Disposición para C2 |
|---|---|---|---|
| **Semantic specialist runtime** | **MISSING** | `lf_router_intent_handoff_v2` y `lf_router_semantic_resume_validate_v1` solo aparecen en migraciones/tests de RW1-04; no existe consumer runtime no-test | implementar **T2 shadow** reutilizando ABI V2; sin ruta/operación/efecto propios |
| **Caller interaction layer** | **MISSING** | `CALLER_INTERACTION_LAYER` y `CLARIFICATION_REQUIRED` solo existen en contrato/tests | materializar interacción acotada: 1 pregunta máxima solo si hay ambigüedad material; nunca autoriza efecto |
| **Profile Runtime / EJECUCION_PERFIL_LF** | **PARTIAL / APPLICABLE** | worker actual entra por ACT-0001 y ledger canónico; step contracts vigentes | reutilizar como consumer real downstream; corregir/componer receipts y demostrar ciclo post-refactor |
| **Merge Train / ACTUALIZACION_DB_LF** | **CURRENT CONTROL / APPLICABLE** | ejecuciones actuales COMPLETED con Router authority + closure evidence; preflight/patch/verify enforced | usar como canario E2E de autoridad/efecto; **no requiere reparación arquitectónica en C1** |
| **Input Governance** | **CONDITIONAL ADAPTER ONLY** | ABI RW1-03: receiver solo cuando aplica | no convertirlo en entrada universal ni selector |

La arquitectura ganadora define al semantic specialist como **un nuevo componente compartido on-demand**, no como un perfil existente y no como segundo Router. Su única responsabilidad es normalizar metas, exclusiones, condiciones y ambigüedad; ACT-0001 conserva discovery, derivation, currentness, operation selection y effect-authority binding.

## 4. Revalidación diferencial de A16Q_C2

### A16Q-C2-G01 — clasificación temprana de parcial/completo
**No se hereda como diagnóstico cerrado.** RW1-04 cambió el handoff semántico, pero todavía no existe consumer V2 que permita volver a ejecutar los casos. Debe revalidarse en C2 con el nuevo flujo; no se presume resuelto ni vigente por analogía.

### A16Q-C2-G02 — binding Router ↔ ejecución canónica
**Parcialmente mejorado, todavía abierto para Profile Runtime.**

En la ejecución actual inspeccionada `EXEC-PROFILE-RUNTIME-70641106-60d9-450f-9f2e-4df52adfaec6`:
- step `router`: PASS, ACT-0001 server-validated;
- step `input_validate`: PASS con `scope_authority_packet` y digest;
- step `context_admission`: PASS con receipt/digest y JIT;
- pero `lf_operation_execution.manifest` no expone `router_authority_receipt` ni `scope_authority_packet_sha256` en raíz;
- el receipt de cola tampoco expone esos bindings.

La evidencia existe en steps, pero todavía no está compuesta en un receipt terminal unificado consumible por el E2E.

### A16Q-C2-G03 — entrega íntegra de solicitud/exclusiones
**Parcialmente mejorado, requiere prueba post-refactor.**

El step `input_validate` contiene el literal real dentro del scope authority packet y su digest; esto supera el baseline histórico. Sin embargo, no existe ejecución post-RW1-04 que demuestre que el semantic specialist y el runtime real consumieron el mismo literal/exclusiones hasta RAW + readback.

### A16Q-C2-G04 — corpus real de modalidades
**Sigue abierto.** No existe ninguna ejecución Profile Runtime creada después de RW1-04. C2 debe producir evidencia contemporánea; los PASS de septiembre son históricos y no certifican la arquitectura actual.

### A16Q-C2-G05 — source/currentness/output/judge/RAW/readback unidos
**Sigue abierto para Profile Runtime.**

La ejecución reciente inspeccionada termina en cola `BLOCKED / LLAMA_TIMEOUT`, mientras la ejecución canónica permanece `IN_PROGRESS`. Solo 7/11 steps están PASS; los cuatro terminales `execute_profile`, `output_validate`, `semantic_judge`, `report_output` no tienen rows. Por tanto no hay receipt completo del mismo ciclo.

### A16Q-C2-G06 — READ_ONLY no implica autorización
**Permanece como invariante, no como reparación específica.** C2 debe demostrar autoridad explícita y no inferirla de modo READ_ONLY.

## 5. Gaps post-refactor que C2 debe resolver o falsar

### RW105-C1-G01 — semantic consumer T2 ausente
No existe consumer runtime que tome `LF_ROUTER_SEMANTIC_REQUEST_V1`, produzca `LF_ROUTER_SEMANTIC_RESULT_V1` y entregue el resultado a `lf_router_semantic_resume_validate_v1`.

**Primer control:** consumer shadow sin effect authority; ACT-0001 rederiva ruta/autoridad después de resume válido.

### RW105-C1-G02 — caller interaction layer ausente
No existe implementación del owner de aclaraciones definido en RW1-03.

**Primer control:** una única pregunta por ronda, solo cuando la ambigüedad material bloquea resolución segura; ninguna pregunta si la respuesta es derivable y ninguna aclaración autoriza efectos.

### RW105-C1-G03 — receipt terminal Profile Runtime no compone toda la autoridad
El ledger pre-runtime ya contiene Router, scope authority y context receipts, pero esa autoridad no está unificada en manifest/receipt terminal y no existe evidencia post-refactor.

**Primer control:** mismo `request_id` + canonical `execution_id` + literal/hash + Router receipt + scope packet + source + context + RAW + validator + semantic judge + readback.

### RW105-C1-G04 — no existe canario Profile Runtime post-refactor
Cero ejecuciones `EJECUCION_PERFIL_LF` posteriores a RW1-04; por tanto no hay prueba material de continuidad con V2.

**Primer control:** ejecución real autorizada y cero-cost del consumer aplicable; si el runtime real no está disponible, C2 queda BLOCKED y no se reemplaza por fixture/simulación.

### RW105-C1-G05 — terminal reconciliation incompleta
Existen filas de cola BLOCKED/FAILED cuyo canonical execution sigue `IN_PROGRESS`.

**Primer control:** C2 debe exigir terminalidad coherente y readback del mismo lifecycle; no cerrar con queue terminal + canonical execution abierto.

## 6. Distinción de hashes que C2 debe preservar

En el caso inspeccionado:

- SHA-256 UTF-8 del literal de cola = `6a9abc7b15a4c4c3ea53b1bb85f403321f84c133a3e8723146b6af9b0cef5a3b`
- `manifest.input_sha256` = el mismo hash, con prefijo `sha256:`
- `lf_operation_execution.request_sha256` = `dc16eee87da8f8e6d6d7824695acae44efdd79b57e8b08ae14f01866bfea8fa1`

No se debe imponer igualdad entre `request_sha256` operativo y el hash literal sin un contrato que diga que representan lo mismo. C2 debe conservar ambos con roles explícitos y demostrar el binding, no “arreglar” el dato por apariencia.

## 7. Contrato mínimo que C2 debe consumir

C2 debe reutilizar lo existente y no crear otro Router/orquestador:

1. **Router:** ACT-0001 conserva discovery, derivation, currentness, operation selection y authority binding.
2. **Semantic specialist:** nuevo consumer compartido on-demand en shadow, sin discovery/routing/operation/executor/effect authority.
3. **Resume:** hash/currentness/subset/scope/exclusions/forbidden authority fail-closed; success vuelve a ACT-0001 para rederivación.
4. **Clarification:** caller-owned, máximo 1 pregunta material; no preguntas redundantes.
5. **Profile Runtime:** usar la operación y step ledger existentes; componer receipts en vez de inventar lifecycle paralelo.
6. **Train:** usar la ruta existente `ACTUALIZACION_DB_LF → MIGRATION_VIA_MERGE_TRAIN` como canario de autoridad y efecto.
7. **Negativos mínimos:** Router bypass, stale semantic result, target adicional, exclusión eliminada, operation/executor/effect devueltos por specialist, runtime no autorizado, receipt faltante.
8. **Positivo material:** al menos un recorrido real contemporáneo con IDs/RAW/readback del mismo request; fixture/mock/synthetic/historical replay no puede cerrar C2.
9. **Terminalidad:** queue, canonical operation, judge y consumer receipt deben reconciliar el mismo lifecycle.
10. **Sin activación implícita:** T2 shadow no equivale a T3 cutover ni T4 legacy retirement.

## 8. Dictamen C1

**Fuente suficiente para abrir C2, con gaps explícitos.**

- RW1-04 quedó cerrado y T1 está instalado.
- Semantic consumer y caller interaction todavía no existen en runtime.
- Profile Runtime tiene una cadena pre-runtime considerablemente más fuerte que el baseline A16Q, pero no existe canario post-refactor ni receipt terminal unificado.
- Merge Train ya demuestra hoy una cadena gobernada completa y debe reutilizarse como control, no repararse.
- C2 debe resolver/falsar los cinco gaps `RW105-C1-G01..G05` con evidencia material; C1 no autoriza ningún efecto ni afirma E2E PASS.
