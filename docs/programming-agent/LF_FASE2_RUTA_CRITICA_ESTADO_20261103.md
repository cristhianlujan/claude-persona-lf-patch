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
