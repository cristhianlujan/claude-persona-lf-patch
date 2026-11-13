# L31 — Ejecución EXACTA de B02 G01 y B03 G02 del documento 12 L28

**Dictamen único:** ambos **ABIERTOS / NO-GO / UNVERIFIED**. Se ejecutó lectura real Supabase, se congelaron IDs y SHA y se reprodujeron positivos/negativos sobre **copias PG18 aisladas**. No se cerraron, reintentaron, recrearon ni modificaron RUN. No se emitieron recibos operacionales ni firmas del dueño.

## Fuente obligatoria y criterio de cierre

- EKB: `INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4`, CANDIDATO VERIFICADO PARCIALMENTE; no usar RUN históricos para acreditar nuevas ejecuciones ni writers desde inspección.
- **Plan solicitado:** [L28 documento 12](https://github.com/cristhianlujan/claude-persona-lf-patch/blob/lf/issue-3779-lote28-blocker-closure-plan-v1/audits/rule-quality-lote28/12_criterios_cierre_motor_7.md). Al iniciar: blob `7541d3844523728096f1da34be8303b1b22662db`; **relectura posterior de L28 vigente: blob `130d474921e0ad010e94a645a8f350f3ca86e611`**, con los textos de B02/G01 y B03/G02 **idénticos**. La rama origen recibió un commit concurrente sobre B07 y otros documentos; no se mezcló ni se rebasó el alcance. Recibos B02/B03 siguen vacíos.
- **SQL original R01 exacto:** `audits/rule-quality-lote19/02_runs_diagnostic_select.sql` blob `d0885393fe987c723f39f464b007d4c489029540`. Historias L19 `01_runs_232_readback.csv`, `03_32_prioritarios.md` y L21 S21_01/H2.
- **Base temporal Supabase:** proyecto `mhwmirqcgxxukpctffuv`, DB `postgres`, rol `supabase_read_only_user` (verificado por SELECT). **SOLO SELECT**. PostgreSQL real de origen 17.6; destino de ensayo PG18.7.

## B02_RUN_SCOPE — G01

| Prueba exacta exigida L28 | Ejecución y evidencia | ¿Satisface cierre G01? |
|---|---|---|
| R01/S21_01 actualizado | **EJECUTADO**: R01 en Supabase live; corte canónico `2026-11-13T07:32:11.933662+00:00` | Parcial. Consulta y hash sí; dueño no ha congelado alcance |
| Enumeración literal de cada ID | **234/234** IDs únicos en snapshot y CSV. Todos `IN_PROGRESS` en ese corte | **Sí para este as_of**, no para cohorte operativa firmada |
| Comparación histórica 232 | **232/232 IDs históricos presentes**, +2 nuevos, 0 salidas del corte L19 | **Sí como conciliación técnica**, sin firma/custodia |
| Cohorte 32 | 32/32 del **TOP 32 propuesto L19** siguen en estado IN_PROGRESS; 32 más recientes por ranking B>C>A>D tienen **31/32 superpuestos** | **NO**: TOP 32 es sugerencia L19, no IDs originales firmados |
| PR #3803 61 RUN | L28 informó un corte de **61**, pero no se entregaron mismos IDs, filtro y `as_of`; **no es posible reconciliar 61=232=234** | **NO**: falta denominador y recibo de contexto de la lectura PR |
| Negativos | PG18 PASS: falta 1 ID, duplicado PK, alteración de payload y adición posterior al corte detectados; rollback | **PASS de seguridad del ensayo**, no certifica operación viva |
| SHA / readback | SHA-256 canónico de texto JSONB de origen revalidado en PG18; bytes fuente y contenido recuperables | **PASS técnico**, pero no acta de custodia/owner |
| Firma y ámbito | **Ninguna firma real / actor de custodia / decisión sobre 32 versus universo completo** | **NO** |

**B02 SHA-256 canónico vivo (corte definitivo de evidencia):** `d14568937e82995b0c141cd8be75bc7091fb0076164933209e0c616b1d564acc`. Comparador histórico L19 R01 232 SHA-256 `b8f0cd33b2c288aff482619ec4873e64c119b6c9121e7a4c2c478db10d4b65e0`.

**Dos RUN adicionales frente a L19** (no implica autoridad para tocarlos):
1. `EXEC-BOOTSTRAP-PROMOCION-REGLA-LF-R43378647210` — `VULNERABILITY_COVERAGE_REPAIR_LF`, señal de efectos B.
2. `EXEC-PROFILE-GATE2-40471E6F661A53D7CE7A4A1B` — `EJECUCION_PERFIL_LF`, clasificación C.

**Comparación 32 con ranking actualizado:** entra `EXEC-BOOTSTRAP-PROMOCION-REGLA-LF-R43378647210`; sale del TOP32 recalculado `EXEC-S30-R19-AUTONOMOUS-20260915-001`. El último **sigue en la población viva**, solo cambia su posición de prioridad. Por tanto ni los 32 antiguos ni los 32 recalculados son decisión vinculante del dueño.

**Volatilidad observada:** R01 pasó por 234 y 235 en lecturas sucesivas, y la posterior congelación canónica volvió a 234. Los hashes dependientes de `now()`/estado no son identidad estable entre cortes. Toda selección futura requiere `as_of`, universo literal firmado, SHA y cotejo de cambios posteriores.

**Falta para cerrar B02:**
- **Dueño LF:** decisión y firma formal de universo y de los **32 IDs literales** (o autorización expresa de nueva cohorte); exclusiones/riesgo y aceptación del conteo 61 como filtro distinto o equivalente, con prueba.
- **Operaciones/Gobernanza:** custodio, freeze operativo de 234 o población elegida a hora exacta, ID/hash del recibo, clasificación por proyecto/perfil y negativo ante alta/cambio posterior.
- **DBA/Operaciones del Merge Train #3803:** exportar lista de 61 con condición SQL, fecha y versión, conciliar con los 234 por ID, no por número.
- **Auditor independiente / registrador oficial:** verificar recibo G01, autor y SHA bajo el carril correcto. No se encontró firma ni se emitió recibo con este lote.

**DICTAMEN G01:** **EJECUCIÓN TÉCNICA PARCIAL, CRITERIO DE CIERRE NO CUMPLIDO. ABIERTO.**

## B03_RUN_EFFECTS — G02 (depende B02)

**Población congelada para prueba B03:** los 234 IDs exactos B02, sin filtrar por estado a posteriori. Lectura `2026-11-13 07:32:15.742705+00`. En el snapshot B03 los 234 RUN seguían `IN_PROGRESS`, sin ausentes. Per RUN hay preimagen SHA-256 de fila completa `public.lf_operation_execution`, hash de pasos completos, hash de guard completo, resumen de estado, owner de lease, `lease_fence`, `checkpoint_seq`, hashes de idempotency key y dispatch key, guard receipts (sin revelar payload), indicios de writes y destino. No se invocaron funciones escritoras.

| Control L28 G02 | Ejecutado, resultado | Límite de cierre |
|---|---|---|
| RUN_PREIMAGE por ID | **234/234** preimágenes SHA; 234/234 con hash de pasos y guard | PASS de lectura, no recibo firmando el efecto |
| Estados y pasos | 234 IN_PROGRESS, 79 RUN con pasos; 29 `github_write` positivo | Evidencia de paso ≠ efecto final conciliado |
| Sinks DB observados por R01 | **21 RUN con `total_direct_sinks>0`** sobre tablas inspeccionadas | Revisar por ID/PK/commit destino; fuentes externas no cubiertas |
| Guards | **6 RUN con al menos 1 `SUCCEEDED`**, sin recibo vacío en esos guards; 1 RUN con `RESERVED` | Recibo local no acredita el efecto en destino; RESERVED requiere resolución |
| Idempotencia | **204 RUN tienen clave**, **0 duplicados encontrados** en `lf_operation_execution`; 0 duplicados dispatch observados en guards | La ausencia de duplicados no prueba replay seguro ni claves de todas las salidas |
| Leases / heartbeat | **8 vencidos**, **0 vigentes**; sin heartbeat worker material acreditado | 8 `LIVENESS_RECEIPT` faltantes; vencimiento no significa worker muerto |
| GitHub externo | **29 referencias `github_write`, 28 únicas**: **29/29 referencias apuntan a commits/PR existentes**, verificación GitHub read-only | Solo prueba existencia; no firma `EFFECT_RECON_RECEIPT` ni vínculo causal con RUN |
| Negativos PG18 | `SUCCEEDED` sin recibo, duplicado de clave, estado alterado, ocho leases sin liveness, fail-closed por efectos externos pendientes | PASS en copia PG18, **no ejecutó reintentos reales** |
| Identidad/recibos | `EFFECT_RECON_RECEIPT` y `LIVENESS_RECEIPT` por RUN **NO ACREDITADOS** | Impide aceptar G02 |

**B03 SHA-256 canónico vivo:** `ec233aa608d66167f9a0206cac3f4db9d0e40167fbf6daf15437b06e8ea3b60f`. Las referencias de GitHub se cotejaron por objeto, **no** por efecto ni intención; no se ha probado nada en proveedores de pagos u otros repositorios no enumerados.

**Falta para cerrar B03:**
- **Operaciones/DBA:** reconciliación **por cada RUN de la cohorte que el dueño firme**, con `RUN_PREIMAGE`, state, pasos, identificador de cada write/guard, sink DB con PK/hash antes/después y `EFFECT_RECON_RECEIPT` oficial. No usar silencio de log como inexistencia de efectos.
- **Custodios de GitHub, Edge, proveedor y workers:** verificar que los commits/PR y efectos externos correspondan al RUN y a su intención, devolver hash de contenido, identidad de ejecución, `dispatch_key`, receipts firmados, resultado de cualquier intento parcial y prueba de idempotencia **sin reejecutar los RUN**.
- **Operaciones de runtime/worker:** evidencia de heartbeat/liveness/lease fence para ocho leases vencidos y **LIVENESS_RECEIPT** por ID; resolver si activo, abandonado, reservado o efecto ya cumplido.
- **Dueño + Operaciones:** clasificar A/B/C/D por RUN con decisión de tratamiento y riesgo, firmar el universo B02; no autorizar retries, cierre o compensación hasta cotejar todas las evidencias.
- **Auditor/registrador autorizado:** emitir recibo G02 solo después de pruebas y negativa de efecto sin recibo, duplicación y lease sin liveness.

**DICTAMEN G02:** **LECTURA TÉCNICA AMPLIA + NEGATIVOS EN COPIA, CRITERIO DE CIERRE NO CUMPLIDO. ABIERTO.**

## PG18 — prueba reproducida sobre copia de datos reales

**CI** [GitHub Actions #43386747597](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43386747597) · Job `131756962233` · PostgreSQL **18.7** · **SUCCESS, 16/16 PASS**, artifact `l31-b02-b03-pg18-raw-run` ID `14019400418`, ZIP SHA-256 `98e9ac8d37432c3d827f5eea33bac136e9a39a378e2a2b973dd981379a5f8a40` (retención 30 días).

**JSON RAW del runner SHA-256:** `1ccce4c1bd2abf9fc4f8667c4b5898ec9e02af08e169980adc9fc355fb1772cb`.

El origen usa JSONB PostgreSQL 17.6 y el banco aislado PG18.7. Los primeros intentos fallaron porque la serialización tipada de `jsonb` de ambos motores no conserva necesariamente el mismo SHA byte a byte: **no se falseó un PASS**. La corrida final capturó **el texto JSONB canónico original completo** (no una reserialización del cliente), comprobó su SHA-256 **directamente en PG18** y luego importó sus registros a tablas estructuradas para comparar ID/campos, guardas y negativos. La huella del JSONB reserializado por PG18 difiere; **no es el SHA de integridad usado para demostrar la copia de bytes**. El banco PG18 es desechable y se elimina al finalizar.

**Cobertura de 16 PASS:** lectura de fuentes, importación 234/234, hashes canónicos B02/B03, reconciliación 232/32, readback B03, cuatro negativos de B02, tres negativos de B03, bloqueos por leases y efectos externos, rollback SHA de copias intacto. No se ejecutó ningún writer RUN real, replay real, merge, DML/DDL Supabase o producción.

## Artefactos y trazabilidad

| Pieza | Archivo |
|---|---|
| R01 literal actual 234 | `01_b02_r01_live_cohorte_jsonb.json` + `02_b02_cohorte_ids.csv` |
| B03 por RUN | `03_b03_run_effects_live.json` + `04_b03_per_run_readback_234.csv` |
| Canonical bytes B02/B03 | `06_b02_canonical_live_jsonb_text.json` + `07_b03_canonical_live_jsonb_text.json` |
| Existencia GitHub | `09_b03_github_check_batch_00..03.json` + `10_b03_github_object_existence_summary.json` |
| Reproducción PG18 | `sandbox/lf_contract_gate_test/rule_promotion_v1/test_pg18_l31_b02_b03_snapshot.py` |
| Workflow | `.github/workflows/l31-b02-b03-run-forensics-pg18.yml` |

**No marcar los recibos de L28**, y no cambiar Estado de G01/G02 hasta recibir evidencia auténtica. El tablero Motor temporal sigue **0/7 cerrados**; B02/B03 **0/2**; los **14 bloqueos L21 siguen abiertos**.

**Autor del diagnóstico:** GPT-6, no auditor independiente ni Claude acreditado. **Resultado: B02_ABIERTO, B03_ABIERTO; producción NO-GO / UNVERIFIED.**
