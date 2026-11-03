# LF — Fase 2 del Agente de Programación: ruta crítica y estado verificable

> **Documento maestro de seguimiento** · Corte: **2026-11-03** · Owner: plan Fase 2 (Paulo) · Estado documental: `SNAPSHOT_READ_ONLY / NO_AUTORIDAD_PRODUCTIVA`  
> **Plan formal (Supabase):** `PROGRAMMING_AGENT_PROGRAMMING_REMEDIATION_V1`.  
> **Fuente de verdad de estado oficial:** `programacion.engineering_plan_units` y `programacion.engineering_work_checkpoints` en Supabase `mhwmirqcgxxukpctffuv`.  
> **Fuente de evidencia técnica:** PR y commits exactos de GitHub. Un CI verde **NO** cambia por sí mismo un checkpoint `PENDING`.

## 0. Cómo leer este plan (evitar volver a empezar por error)

Hay **tres estados distintos**:
1. **Estado oficial Supabase:** `PENDING`, `DONE` u otro valor real del ledger. No se sustituye con opiniones ni pruebas sintéticas.
2. **Madurez de implementación:** no localizado / candidato source-only / probado offline / integrado con autoridad / ejecutado con recibos reales.
3. **Bloqueo operativo:** autoridad, fuentes CURRENT, proveedor real, recibo, selector, despacho, revisor, etc.

**Resultado del readback del 03/11:** **108/108 checkpoints `PENDING`**, en PG-00…PG-20. Esto **no significa** que no exista trabajo: los PR de implementación descritos abajo existen y tienen pruebas técnicas previas, pero no se fusionaron/admitieron ni generan recibos operativos. La ruta crítica de cinco etapas es **una vista ejecutiva derivada**, no cinco unidades adicionales de Supabase.

### Resumen formal Supabase por unidad

| Unidad | Checkpoints | Estado oficial |
|---|---:|---|
| PG-00 | 11 | 11 PENDING |
| PG-01 | 7 | 7 PENDING |
| PG-02 | 5 | 5 PENDING |
| PG-03 | 10 | 10 PENDING |
| PG-04 | 7 | 7 PENDING |
| PG-05 | 5 | 5 PENDING |
| PG-06 | 5 | 5 PENDING |
| PG-07 | 6 | 6 PENDING |
| PG-08 | 8 | 8 PENDING |
| PG-09 | 5 | 5 PENDING |
| PG-10 | 5 | 5 PENDING |
| PG-11 | 5 | 5 PENDING |
| PG-12 | 4 | 4 PENDING |
| PG-13 | 3 | 3 PENDING |
| PG-14 | 3 | 3 PENDING |
| PG-15 | 3 | 3 PENDING |
| PG-16 | 3 | 3 PENDING |
| PG-17 | 3 | 3 PENDING |
| PG-18 | 3 | 3 PENDING |
| PG-19 | 3 | 3 PENDING |
| PG-20 | 4 | 4 PENDING |
| **TOTAL** | **108** | **108 PENDING** |

## 1. Ruta crítica ejecutiva (etapas 0–4)

| Etapa | Unidad formal / propósito | Lo que SÍ tenemos | Lo que falta para una prueba/autoridad real | Estado práctico |
|---|---|---|---|---|
| **0. Base y gobernanza** | PG-00: contratos, estándares, Skills, circuito de cambios, pipeline | C6/selector source-only, C9 cambios, C3 preflight/planificador, ruta existente de CI y PASE. PR #13/#16/#17 en sandbox; PR #3372 para gate contextual | Publicación gobernada catálogo C3, decisión niveles L1/L2, ejecutor real/pre-model, permisos y recibos de fuente; no asumir despliegue | **Base extensa, NO_GO productivo** |
| **1. Entrada de Análisis** | PG-01: admitir paquete A9 | Contratos/guarda, componentes candidatos C3/C4/C5/C7; writer V2 existente en PR #3193 | **C6**: A9 real CURRENT, juicio independiente, recibo `ACCEPT` gobernado, consumo acreditado; sin él no existe entrada aprobada | **Bloqueo principal** |
| **2. Clasificación técnica** | PG-02: dominios, stack, alcance | 5/5 checkpoints cuentan con componentes o evidencia source-only; C5 con muestra independiente PR #3517 | Usar **mismo run** PG-01 y recibos reales; admisión/ejecutor y bindings. No llamar 5/5 `DONE` | **Candidato técnico, no oficial** |
| **3. Estrategia y aseguramiento** | PG-03: preparar estrategia y revisar antes de construir | C1/C3/C4/C5/C6/C7/C8/C10 tienen PR candidatos; C2 catálogo/skills/L3/precedencia; C9 preflight/revisión de lectura | Catálogo C3 vigente, clasificación L1/L2 por regla, fuente L3 B autenticada, estrategia C3 real, `EVIDENCE_LEDGER` VERIFIED, despacho/juez independiente C9 | **Candidato con bloqueos documentados** |
| **4. Construcción y entrega** | PG-04…PG-20: plan de implementación, cambios, pruebas, QA, publicación/entrega | Contratos y componentes parciales de repositorio; **no se certifica progreso de todos los checkpoints sin auditoría particular** | Handoff de estrategia PG-03_C8/C9 real, PG-04 y siguientes en secuencia de plan y pruebas con autoridad | **Aún sin ejecución operativa acreditada** |

> **No confundir:** “etapa 3” es el bloque de estrategia **PG-03**, no “PG-03 completado”. La etapa 4 **agrupa** PG-04…PG-20 y no debe reducirse a un único checkpoint de código.

## 2. Estado de checkpoints de la ruta activa

### PG-00 — Base / gobernanza

- **Oficial:** C1…C11 = `PENDING` (11/11).
- **Técnico:** inventario PG-00 (108 checkpoints), catálogo C3 con precalificación, C6 Skills/circuito cambios, resultados independientes y PRs previos en repositorio. No se convierte ese historial en 11 cierres oficiales.
- **PRs clave:** [Carril E #3372](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3372), [sandbox estándares #13](https://github.com/paulozterra/lf-programming-sandbox/pull/13), [selector C6 #16](https://github.com/paulozterra/lf-programming-sandbox/pull/16), [inventario decisión STD-API #17](https://github.com/paulozterra/lf-programming-sandbox/pull/17).
- **Bloqueos:** C3 writer/publicación gobernada, owner debe decidir nueve reglas STD-API (L1/L2 o división) por C9, fuente/runtime pre-model real del Carril E. No abrir otro selector/otra publicación por duplicado.

### PG-01 — Entrada A9 de Análisis

| Checkpoint | Avance técnico conocido | Falta |
|---|---|---|
| C1–C2 | Contratos de entrada/recepción y exact receipt guard existentes (source-only) | Atestación y cierre gobernado |
| C3 | [#3513](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3513) — alcance y matriz, prueba candidata | Fuente A9 real CURRENT |
| C4 | [#3515](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3515) — marco técnico y fuentes, candidato | Readback real de repo/HEAD/perfil |
| C5 | [#3514](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3514) — negativos y reutilización de huella, candidato | Validación en ejecución gobernada |
| **C6** | [#3193](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3193) — writer y envelope V2 en draft | **Recibo real ACCEPT persistido, juez A9, currentness y lectura PG-01 autorizada** |
| C7 | [#3516](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3516) — suficiencia, candidato | Evidencia real y decisión por alcance |

**Paquetes A9 encontrados (SQL real, 03/11):**
- `private.lf_decision_context_asof_v1` conserva 3 snapshots:
  - `B2B_APP_SHELL v1.0`, `context_id=e5adcfbf-e53f-420d-a94a-fad553fa6e48`: 9 scopes, 10 frentes canónicos, 15 relaciones, `NEED_MORE_EVIDENCE`, `PARTIAL_READY` como verdict de paquete, `CANDIDATO_NOT_ADMITTED` como autoridad; 0 scopes READY.
  - `B2B_APP_SHELL v0.9`, `context_id=38a8f5c8-a6f3-45d6-b1ee-823af130e647`: histórico `PARTIAL_READY`, sin matriz canónica, 5/9 READY históricos; no es CURRENT.
  - `B2B-OFERTA-001`, `context_id=41f0287a-c7db-4f34-b2f7-c548fa534ece`: histórico parcial, matriz ausente.
- En `private.lf_programming_context_handoff_receipts_v1`: **0 filas, 0 `ACCEPT`**. `private.lf_pg01_subject_verifications_v1` y `private.lf_pg01_review_attestations_v1`: 0 filas cada una.
- **Prueba corta ya hecha** sobre v1.0: la llamada directa al resolver `private.fn_lf_programming_context_handoff_receipt_resolve_v2` desde usuario de solo lectura falló `permission denied`. No repetir fixtures ni alegar que el resolver productivo dio PASS. Requiere ejecución autorizada.
- `programacion.context_packs`: 27 inventarios técnicos; **no son handoff A9** aunque estén COMPLETE.

**Decisión para no perder tiempo:** no repetir pruebas históricas de paquetes sin una nueva señal material (recibo A9 admisible o acceso del ejecutor autorizado). Los snapshots son útiles para **pruebas de recepción/negativos**, no para autorizar programación.

### PG-02 — Clasificación técnica

- **Oficial:** C1–C5 todos `PENDING`.
- **Técnico:** C1–C4 tienen contrato/componentes previos; [#3517](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3517) agregó revisión de muestra con oráculo congelado. **5/5 source-only no significa 5/5 terminado.**
- **Pendiente:** PG-01_C6 real, fuente/commit vigente, registro de ejecución y bindings PG-02 exactos. Evitar copiar/reescribir clasificadores existentes.

### PG-03 — Estrategia técnica

**Oficial:** C1…C10 = `PENDING` (10/10).

| Checkpoint | Evidencia de avance (PR draft OPEN) | Pendiente de cierre |
|---|---|---|
| C1 | [#3497](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3497) — stack exact HEAD | Fuente/lectura de commit real |
| **C2** | [#3518](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3518) catálogo, [#3519](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3519) skills, [#3521](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3521) L3 B, [#3522](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3522) precedencia | C3 release CURRENT, niveles L1/L2 para 9 STD-API, L3 real y precedencia semántica autorizada, selector atestado |
| C3 | [#3498](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3498) — estrategia candidata reusa particionado | Estrategia productiva exacta y recibo EVIDENCE_LEDGER |
| C4 | [#3499](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3499) — REUSE_AS_IS | Prueba integrada con A9 real |
| C5 | [#3500](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3500) — reglas mínimas por dominio | Jueces deterministas + semánticos en ejecución real |
| C6 | [#3507](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3507) — suficiencia | Reconsulta gobernada de Análisis si falta decisión |
| C7 | [#3508](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3508) — waivers y políticas existentes | Decisión humana y autoridad readback |
| C8 | [#3509](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3509) — handoff PG-04 | C9 verificado y admisión productiva |
| **C9** | [#3523](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3523) — preflight revisor; [#3524](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3524) — sondeo Supabase real y ruta C3→Ledger→C9 | Estrategia real, recibo VERIFIED, dispatch, revisión independiente ejecutada/persistida |
| C10 | [#3510](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3510) — D14/D15 | Confirmación arquitectura con autoridad vigente |

**Evidencia técnica confirmada en sesiones previas:**
- Selector original C6 [#16](https://github.com/paulozterra/lf-programming-sandbox/pull/16): **80/80 tests, 5/5 jobs PASS** (HEAD `0ee4bcd350c6241a6bb481ecb4a10b38152d2e07`); requiere revisión independiente/owner C9.
- Inventario niveles `STD-API-01..09` [#17](https://github.com/paulozterra/lf-programming-sandbox/pull/17): **83/83 tests, 5/5 jobs PASS**, pero asignación individual nivel **0/9** decidida.
- C2 [#3521](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3521): L3 **1 positivo +16 negativos PASS**; es formato fixture candidato, no contrato L3 aprobado.
- C2 [#3522](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3522): precedencia **1 positivo +18 negativos PASS**; `precedence_verified=false` hasta readback semántico real.
- C9 [#3523](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3523): **1 positivo +10 negativos PASS**; reutiliza `INDEPENDENT_ASSURANCE` y preflight, **no ejecuta** revisor semántico.
- C9 [#3524](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3524): lectura real: `pg01_c6/pg03_c2/c3/c9=PENDING`; `verified_subjects=0`, `enabled_pg03_c3_c9_bindings=0`, `actual_pg03_review_runs=0`; `INDEPENDENT_ASSURANCE` CURRENT disponible, operación gobernada disponible, 2 resolutores confiables activos. **Primer bloqueo = PG-01_C6**. PASE y Router Level2 SUCCESS.
- No crear otro juez, writer, resolver o selector por encima de las capacidades ya existentes; usar `fn_lf_evidence_ledger_anchor_v1` y `lf_independent_review_begin_v3` por ruta autorizada, nunca mediante SQL manual ad hoc.

### PG-04…PG-20 — Construcción, pruebas y entrega

- **Oficial:** todos los checkpoints de esas unidades `PENDING`.
- Hay contratos e implementaciones parciales anteriores en varias ramas; este corte **no certifica** cada componente posterior ni presume que están vacíos.
- La admisión operacional para PG-04 debe esperar una estrategia PG-03_C8/C9 autorizada. Auditar cada etapa contra sus evidencias cuando se habilite; no crear trabajo por desconocer código previo.

## 3. Cadena mínima de desbloqueo: lo siguiente que verdaderamente cambia el estado

```text
A1–A9: paquete real CURRENT + juicio independiente (no fixture)
      ↓
PG-01_C6: receipt ACCEPT gobernado + readback exacto
      ↓
PG-02: clasificación ligada al mismo run + comprobación productiva
      ↓
PG-00/C3/C6 + PG-03_C2: catálogo publicado, niveles L1/L2, L3 B, skills atestadas
      ↓
PG-03_C3: estrategia real con hash/commit/source CURRENT
      ↓
EVIDENCE_LEDGER: receipt SOURCE_SNAPSHOT VERIFIED
      ↓
PG-03_C9: INDEPENDENT_ASSURANCE real + veredicto independiente
      ↓
PG-03_C8: handoff a PG-04
      ↓
PG-04…PG-20: implementación, pruebas, publicación y entrega
```

**Primer bloqueo operativo observado hoy:** `PG-01_C6` sin un A9 aceptado y un recibo real; **no resolverlo repitiendo pruebas con paquetes históricos**. Otros bloqueos independientes pueden avanzar en paralelo (decisión L1/L2, revisión C3). Solo registrar `DONE` mediante autoridad y validador oficial.

## 4. Evidencia base y métodos de verificación repetibles

### Supabase — readback oficial de unidades y checkpoints

```sql
SELECT u.unit_code,
       count(*) AS total,
       count(*) FILTER (WHERE c.status='PENDING') AS pending,
       string_agg(DISTINCT c.status, ', ' ORDER BY c.status) AS statuses
FROM programacion.engineering_plan_units u
JOIN programacion.engineering_work_checkpoints c
  ON c.work_item_id=u.work_item_id
WHERE u.plan_code='PROGRAMMING_AGENT_PROGRAMMING_REMEDIATION_V1'
GROUP BY u.unit_code
ORDER BY lpad(regexp_replace(u.unit_code,'[^0-9]','','g'),2,'0');
```

### Supabase — readback de bloqueo de PG-01_C6

```sql
SELECT count(*) AS all_receipts,
       count(*) FILTER (WHERE verdict='ACCEPT') AS accepted
FROM private.lf_programming_context_handoff_receipts_v1;

SELECT count(*) AS subject_verifications
FROM private.lf_pg01_subject_verifications_v1;

SELECT count(*) AS review_attestations
FROM private.lf_pg01_review_attestations_v1;
```

### PG-03_C9 — sondeo operativo de solo lectura

Ruta versionada en [PR #3524](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3524):
`sandbox/lf_contract_gate_test/programming_agent_four_stage/pg03_strategy_candidate/pg03_c9_real_runtime_readiness_v1.sql`.

### GitHub — estado de implementación

Usar el **HEAD exacto** y estado OPEN/DRAFT/MERGED de cada PR citado; no asumir que CI de una rama heredada equivale al estado de main. Los PR #3497–#3524 de PG01–PG03 y #3193, #3372, #13, #16, #17 consultados al corte estaban **OPEN DRAFT**. Una dependencia apilada no equivale a merge.

## 4.1. Auditoría puntual A9→PG-01_C6 (03/11, sin repetir paquetes)

Se releyeron en **Supabase vivo, solo lectura**, las firmas, grants y registros de las piezas existentes; y en GitHub los PR [#3193](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3193) y [#3320](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3320). Resultado:

| Pieza | Evidencia actual | Dictamen |
|---|---|---|
| Escritor runtime PG-01 | `private.fn_lf_programming_receipt_record_runtime_v1(p_source_execution_id,p_router_action_binding,p_programming_handoff,p_judge_execution_id)` existe; `service_role` tiene EXECUTE | **Implementado en SQL**, no falta crear otro |
| Receptor PG-01 | `private.fn_lf_programming_context_handoff_receive_v1(context_id,context_sha256)` existe | Implementado, sin prueba completa con productor real |
| Resolver D7/V2 | `private.fn_lf_programming_context_handoff_receipt_resolve_v2(binding)` existe, no accesible directamente desde identidad RO | No intentar conceder GRANT ni atribuir PASS a una llamada denegada |
| Perfil de Análisis A1–A9 | Fuente candidata `profiles/programming_analysis_lf/`; no listado en las 10 filas de `public.lf_profile_selection_registry_v1` CURRENT | **No se encuentra registrado en el selector operativo examinado** |
| Ejecución real | `lf_operation_execution` con perfil de Análisis en target o manifest: 0 | No existe prueba operacional de productor válido |
| Recibos de handoff | `private.lf_programming_context_handoff_receipts_v1`: 0/0 (total/ACCEPT) | Primer handoff productivo no realizado |

**Interpretación exacta:** el escritor de #3193 **sí está en Supabase** y el flujo SQL tiene las piezas principales; el bloqueador más temprano identificado es la **ausencia de perfil A1–A9 registrado CURRENT, despacho con fuente/autoridad y ejecución `EJECUCION_PERFIL_LF` finalizada con juicio independiente**. Un perfil fuente candidata no se habilita por copiar archivos ni por GREEN CI. No usar paquetes históricos para `ACCEPT`.

**Siguiente trabajo del dueño de Análisis/Router**: calificar la fuente de Análisis A1–A9 y sus contratos, registrar el perfil mediante la gobernanza existente; verificar Router→`EJECUCION_PERFIL_LF`, invocar un caso fresco controlado y obtener respuesta real, A9 snapshot CURRENT y revisión independiente; solo después usar el escritor existente, readback de recibo y resolver V2 en ejecución autorizada. No crear escritor, juez ni engine paralelo. Mantener PG-01_C6 `PENDING` hasta prueba real completa.

## 4.2. Bloqueo exacto de registro y despacho del perfil A1–A9 (03/11)

**Se confirmó en GitHub:**
- [PR #2071](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2071), [#2145](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2145), [#2214](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2214) y [#2416](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2416) están **MERGED a main** (12–13/10). **No pedir fusionar otra vez** ni tratar los informes históricos de esos PR como estado de hoy.
- El perfil `profiles/programming_analysis_lf/` está implementado como **CANDIDATE_NOT_RELEASED**. El `analysis_source_binding.json` declara `current_release_verified=false`, `source_readback.tier=GIT_BLOB_EXISTENCE_ONLY`, `external_currentness=NOT_ATTESTED`, `governed_adapter_candidate.router_binding=MISSING` y `activation_allowed=false`.

**Consulta SQL reutilizable y ejecutada contra Supabase:** [`LF_ANALYSIS_A1_A9_ROUTER_SOURCE_ADMISSION_READBACK_V1.sql`](sql/LF_ANALYSIS_A1_A9_ROUTER_SOURCE_ADMISSION_READBACK_V1.sql).

| Precondición real | Resultado |
|---|---|
| `lf_activos`, código `PERFIL-PROGRAMMING-ANALYSIS-LF` | **0** filas |
| `lf_profile_selection_registry_v1` para el código | **0** descriptores |
| `v_lf_router_adapter_bindings` hacia el perfil | **0** bindings |
| `lf_profile_execution_source_eligibility_v1` | `eligible=false`, `PROFILE_NOT_CURRENT` |
| `EJECUCION_PERFIL_LF` atribuible al perfil en registros consultados | **0** ejecuciones |
| `lf_programming_context_handoff_receipts_v1` | **0** filas; **0** ACCEPT |

**Control contrastivo:** `PERFIL-UI-ARCHITECT` sí tiene `lf_activos`, descriptor CURRENT, `repo_path=profiles/ui_architect` y `lf_profile_execution_source_eligibility_v1` devuelve `PROFILE_EXECUTION_SOURCE_READY`; ello solo prueba elegibilidad de fuente, **no** permiso de ejecución. No copiar valores de ese perfil a Análisis.

**Primer bloqueo exacto:** `BLOCK_ANALYSIS_PROFILE_SOURCE_NOT_REGISTERED_OR_ELIGIBLE`. El escritor runtime PG-01 existe, pero no se puede alimentar desde un productor A1–A9 gobernado que no es elegible. Después de resolver el registro habrá que verificar: contrato A1–A9 CURRENT RELEASED, adapter agregado/Router binding atestado, ejecución real con provider receipt, juez semántico independiente, snapshot current y recibo PG-01 ACCEPT; el sondeo no los sustituye.

**Siguiente cambio necesario (en el carril dueño de registros/Router, con autoridad aprobada):** registrar el activo canónico en `lf_activos` con identidad y source GitHub auténticos; publicar descriptor CURRENT en el registro existente mediante su circuito de gobernanza; revalidar `lf_profile_execution_source_eligibility_v1` y agregar solo el binding de adapter requerido. Primero ejecutar el SQL read-only anterior. No habilitar `service_role` ad hoc, no ejecutar el perfil ni modificar registros por un script documental.

## 4.3. Reconciliación de trabajo previo A1–A9 y alta gobernada (03/11)

**Importante: este frente NO es nuevo.** Antes del diagnóstico del Router se trabajaron A9 y PG-01 mediante estos PR, verificados nuevamente en GitHub:

| Componente | PR | Estado Git al 03/11 | Límite |
|---|---|---|---|
| Receptor PG-01, C4/C7, mapping A9 | [#3135](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3135) | OPEN DRAFT | diseño y pruebas; no PG-01 E2E |
| Ensamblador A9, 23 campos | [#3174](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3174) | OPEN DRAFT | funciones puras, no productor runtime |
| Juez A9 mediante capacidad existente | [#3172](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3172) | OPEN DRAFT | adapter puro, no juez ejecutado |
| Envelope V2 y resolver | [#3181](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3181) | **MERGED 29/10** | solo admite recibo auténtico |
| Writer runtime inicial | [#3193](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3193) | OPEN DRAFT | SQL real instalado por cadena posterior |
| Writer final con autoridad | [#3320](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3320) | **MERGED 29/10** | instalado no significa ejecutado |
| Fuentes A1–A9 y perfil de Análisis | [#2071](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2071), [#2145](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2145), [#2214](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2214) | **MERGED 12/10** | `CANDIDATE_NOT_RELEASED` en fuente |

**No reimplementar** A9, receptor, juez, writer ni la guarda de 23 campos. Diferenciar `PR #3193 OPEN` (histórico/candidato) y `#3320 MERGED` (writer de la cadena consolidada). El SQL del writer se confirmó existente en Supabase por firma, no con una ejecución del productor.

**Guardas del inventario comprobadas en vivo**: `public.lf_activos` requiere `id`, `source_spreadsheet_id`, `source_spreadsheet_title`, `source_sheet_name`, `source_row_number`, `migration_batch_id`, `created_by_execution_id` y otros campos. No hay registro del código `PERFIL-PROGRAMMING-ANALYSIS-LF` ni `lf_profile_selection_registry_v1` CURRENT. La mera presencia de su SKILL en GitHub no autoriza inventar procedencia de una hoja, un `migration_batch_id` o un propietario. La función `lf_profile_execution_source_eligibility_v1` responde `PROFILE_NOT_CURRENT`, coherente con ambas ausencias.

**Ruta mínima correcta**: localizar autoridad de alta de activo/perfil y su procedencia válida; obtener aprobación y calificación `CURRENT RELEASED` de los nueve contratos antes de habilitar selección; registrar el activo por ruta gobernada (no `INSERT` manual); generar descriptor fuente vigente y binding Router/adapter, con lectura independiente; ejecutar el perfil mediante `EJECUCION_PERFIL_LF` y juzgar su A9, luego writer ya instalado y readback `ACCEPT`. Si el circuito no admite un perfil nacido en GitHub sin hoja fuente, **es decisión de gobernanza**, no licencia para falsear campos.

**Bloqueo de esta iteración:** `PROFILE_REGISTRATION_AUTHORITY_AND_PROVENANCE_NOT_EVIDENCED`. No se intentó alta SQL de falso origen ni se activó runtime. La ruta actual de solo lectura sigue respondiendo `BLOCK_ANALYSIS_PROFILE_SOURCE_NOT_REGISTERED_OR_ELIGIBLE`.

## 4.4. Rectificación arquitectónica — el Router no es un segundo ingreso obligatorio (03/11)

**Pregunta del owner:** si la solicitud ingresó por Router y completó Análisis, ¿por qué volver a conectarla al Router para ingresar a Programación?

**Respuesta contractual:** **no se debe volver a seleccionar ni enrutar desde cero una petición que conserva el mismo run, contexto y autoridad**. Los contratos `ANALYSIS_PROCEDURE_V1.md`, `analysis_programming_handoff_parity_contract_v1.json` y `programming_entry_contract_v1.json` establecen el **límite directo A9 (productor) → PG-01 (consumidor)** con snapshot exacto, context_id, digests y recibo. No listan una selección semántica del Router como checkpoint intermediario A9→PG-01.

**Lo que la ruta operativa general SÍ hace:** `lf_router_profile_execution_handoff_v1` en Supabase incorpora `reenter_router_before_execution=false`, `return_to_router_after_profile_result=true`. La función `lf_profile_result_router_return_classify_v1` define `REENTER_ROUTER_STAGE1` para determinados retornos tipados del perfil (ej. faltan datos, redirección al orquestador). Es **una continuación condicional**, no permiso para repetir Router ante todo A9 válido. La selección inicial de perfil sigue bajo autoridad Router cuando el Router efectivamente es el iniciador de `EJECUCION_PERFIL_LF`.

**Distinción decisiva pendiente de verificar antes de cualquier alta:** `profiles/programming_analysis_lf` es un **perfil candidato autónomo** (`CANDIDATE_NOT_RELEASED`); su ausencia en `lf_activos` y `lf_profile_selection_registry_v1` sí bloquea **esa vía concreta de selección de perfil**. Pero **no prueba** que el flujo **A1–A9 del agente de programación ya elegido por un Router previo** necesite registrar un perfil separado. Para ese flujo, el contrato que manda es la paridad A9→PG-01 y la operación productor/ejecutor autorizada que efectivamente se haya elegido.

**Decisión de alcance:** NO registrar automáticamente `PERFIL-PROGRAMMING-ANALYSIS-LF` en Supabase como requisito de PG-01_C6, ni reenrutar la petición. Primero rastrear el **`execution_id` original**, identificar el ejecutor efectivo de A1–A9 y leer su handoff A9. Si se usa la alternativa de perfil seleccionado de forma independiente, registrar ese perfil solo con su autoridad y procedencia gobernadas. El bloqueo universal aún comprobado es **0 recibos A9/PG-01 ACCEPT y ninguna ejecución A1–A9 apta acreditada**, no necesariamente la inexistencia del descriptor de este perfil candidato.

**Próxima verificación útil:** trazabilidad de la solicitud original: Router execution/receipt → propietario de análisis → A9 `DECISION_CONTEXT_ASOF` → recibo `PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1` → `resolve_v2` PG-01. Identificar el punto real de continuidad sin otra selección. Conservar los PR previos y no crear un engine o juez paralelo.

## 4.5. Avance independiente PG-03_C5 — integridad del contexto de reglas (03/11)

**PR [#3526](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3526)**, HEAD `ed7c2e9302b1b3707f95206e9fb77de582ddaaa6`, DRAFT, stacked sobre #3524. **No toca Análisis ni habilita programación real.**

- **Defecto hallado** en `pg03_domain_judges_v1.py::deterministic_judge_complete`: el validador verificaba IDs obligatorios, pero no recomputaba `projection_sha256` ni `estimated_tokens`. Modificar contenido de una regla, dominio o `source_catalog_sha256` después de proyectar podía conservar un `PASS_CANDIDATE_ONLY` estructural. También el borrado de una regla ajustando `required_rule_ids` podía ocultarse en la paridad interna.
- **Corrección mínima**: reutilizar el **mismo juez determinista**, conservar sus errores específicos, recomputar digest y tokens sobre todos los campos proyectados antes de devolver PASS candidato. No se creó otro juez/rúbrica.
- **Regresión adversarial** nueva `test_pg03_c5_projection_integrity_v1.py`: 1 positivo y **9 negativos** sobre texto de regla, dominio, texto de regla A, source_ref, SHA catálogo, dominio pedido, SHA proyección, tokens y regla omitida con required IDs acomodados.
- **CI exacto HEAD:** PASE run [#41668732317](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/41668732317) `SUCCESS`; F0 [#41668731730](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/41668731730) `SUCCESS`; Router Level2 Advisory [#41668731830](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/41668731830) **4/4 jobs SUCCESS** incluyendo `router-level2-advisory-contract` que llama a la prueba nueva y a las regresiones previas.
- **Límite:** es **integridad local**, no firma de procedencia. Un productor podría recalcular todo; catálogo de C3 CURRENT, L1/L2, fuente real y juez semántico independiente siguen siendo dependencias. No cambiar `PG-03_C5=PENDING` (Supabase 03/11).
- **Estado de avance técnico:** `PG03_C5_SOURCE_ONLY_INTEGRITY_HARDENED / CI_PASS / NO_AUTHORITY`. **Siguiente avance autónomo**: revisar qué campos de catálogo de PG-03_C2 deben estar ligados a fuente C3 autenticada antes de aceptar el proyector; solo si hay delta comprobable, implementarlo en componente existente, sin rehacer A1–A9.

## 4.6. PG-03_C2 — fail-closed en selección de reglas de precedencia (03/11)

**PR [#3527](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3527)**, HEAD `b1957859d1872574417a345cf9b307a1500d9167`, DRAFT apilado sobre [#3526](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3526). Se reusó `pg03_c2_precedence_candidate_v1.py`, sin nuevo motor, juez, SQL ni cambios a Análisis.

**Brecha concreta:** `selected_rule_ids=[]` anteriormente podía producir `CANDIDATE_NOT_ADMITTED` aun sin regla del catálogo (solo A/B); IDs duplicados se introducían sin rechazo específico y payloads no-string no quedaban bien delimitados. **Delta:** `SELECTED_RULES_INVALID` para lista vacía, IDs repetidos, nulos y tipos incorrectos. Test previo 1 positivo+18 negativos; test ampliado **1 positivo+23 negativos** (5 casos nuevos). La salida candidata no concede autoridad. **CI verificado en HEAD exacto:** PASE [run #41670733904](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/41670733904) SUCCESS; LF Router Level2 Advisory [run #41670733874](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/41670733874) SUCCESS, 4/4 jobs incluido `router-level2-advisory-contract`. Estos controles incluyen la regresión existente ampliada a 1 positivo + 23 negativos; no equivalen a admitir una fuente real.

**Readback oficial:** `PG-03_C2=PENDING` y `PG-00_C3=PENDING`. No hay tabla de catálogo STD-* gobernada inequívoca entre los registros de Supabase inspeccionados (no concluir ausencia absoluta de un catálogo contractual almacenado en otra familia de tablas); **aún no hay release CURRENT/C3 con origen autenticado probado para este consumidor**.

**Bloqueos tras la corrección:** publicación C3 del catálogo, decisión L1/L2 por cada regla `STD-API` mixta, L3 B real y consistente con PG-01_C4, recibo del selector C6 realmente ejecutado, precedencia semántica y punto de despacho. Los PR #3518/#3519/#3521/#3522 ya modelan los límites source-only: **no reimplementarlos**. La siguiente integración debe autenticar fuente/autoridad con mecanismo existente, no aceptar un SHA elegido por el mismo caller.

## 5. Reglas de actualización del documento

1. **Actualizar fecha de corte y SQL** antes de cambiar la columna oficial. No poner `DONE` por pruebas locales.
2. Para cada checkpoint alterado registrar **PR/HEAD, contrato, tipo de prueba, resultado CI, recibo real y bloqueo restante**.
3. Clasificar explícitamente `SOURCE_ONLY_PASS`, `READY_FOR_INTEGRATION`, `RUNTIME_ATTESTED`, `OFFICIAL_DONE` o `BLOCKED`.
4. **Evitar duplicación:** buscar primero PR, función SQL y mecanismo existente; no crear otro gate/rúbrica/evaluador si la capacidad actual lo cubre.
5. Registrar el **primer bloqueo real** y no repetir paquetes/fixtures hasta que una dependencia material cambie.
6. No alterar roles, `service_role`, grants, estados en Supabase o main por actualización documental. Los cambios productivos requieren mandato gobernado independiente.
7. Este documento **sí se mantiene en Git** para persistir entre conversaciones. Cualquier conversación nueva debe comenzar leyendo este archivo y ejecutando el readback de Supabase, nunca desde una afirmación verbal anterior.

---

**Dictamen del corte:** `DOCUMENTED_IMPLEMENTATION_PROGRESS / ALL_OFFICIAL_CHECKPOINTS_PENDING / FIRST_REAL_BLOCKER_PG01_C6`. Este documento no admite ni bloquea por sí mismo un producto; solo registra el plan y su evidencia.
