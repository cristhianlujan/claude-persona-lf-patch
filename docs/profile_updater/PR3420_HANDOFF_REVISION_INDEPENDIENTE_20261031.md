# LF — PR #3420 / Paquete para revisión independiente

**Rol solicitado:** juez independiente de la evolución del Profile Updater (no productor, no reparador).
**Estado del paquete:** candidato DRAFT. **No aprobar, integrar ni promover por el solo hecho de tener CI verde**.
**Repositorio:** `cristhianlujan/claude-persona-lf-patch`
**PR:** https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3420
**Alcance:** Matriz ORIGINAL vs EVOLUCIONADO y destino dinámico por control/perfil. Sin cambios a Router, juez semántico, Grupo 2 oficial, SQL, runtime Edge, permisos ni producción.

## Lecturas obligatorias

1. Leer el **diff exacto de PR #3420** y fijar/registrar HEAD actual (el revisor NO debe utilizar el SHA escrito en este documento si HEAD cambió).
2. Leer `skills/profile_creator/validators/operational_coverage_v1.py` y `compare_s26_profile_evolution_v1.py` en trusted main. Contrastar cada lectura de caso/control contra el comparador oficial.
3. Leer `skills/profile_creator/validators/operational_control_matrix_v1.py`, `scripts/lf_profile_update_run.py` y sus dos suites de tests.
4. Revisar `lf_operation_step_contracts` LIVE, operación `ACTUALIZACION_PERFIL_LF`, pasos `regression_after` y `report_output`. Verificar que los nuevos campos opcionales no alteran el evaluador/recorder existente; consultar función y readback sin escribir.
5. Leer `skills/profile_creator/operational_cases/systemic_root_cause_repair_lf/WEB-001.case.json`, sus dos runs almacenados y `profiles/systemic_root_cause_repair_lf/SKILL.md` en revisión fijada.
6. Leer `docs/profile_updater/WEB001_MAPA_CONTROL_DESTINO_PROPUESTO_20261031.md` como **propuestas**. Cada localizador debe contrastarse con la fuente exacta y con el contrato del consumidor; N1/N2 no son IDs universales de pasos.

## Afirmaciones que se deben falsificar independientemente

| ID | Prueba | Falla si… |
|---|---|---|
| R01 | Trusted root y caso congelado | El candidato puede cambiar los checks del caso o fabricar PASS |
| R02 | Comparación original/evolucionado | No se usan exactamente los resultados `operational_coverage_v1.measure` |
| R03 | Destino del perfil correcto | Un paso de otro perfil se acepta como propio |
| R04 | Hash/anchor exacto | Se acepta título inventado, SHA obsoleto, duplicación o ítem inexistente |
| R05 | Numeración variable | Se fija un código universal `70.1/N2.1` sin definición en el perfil |
| R06 | Bindings de caso | Un binding declarado e inválido produce `GROUP2_PROJECTION_MATCHED_REPORT_ONLY` |
| R07 | Campos de evidencia | La matriz pierde nombre, fuente, línea, SHA, ID de corrida, comparación o atestación |
| R08 | Preservación de contratos | `regression_after/report_output` reemplazan campos o amplían autoridad de PASS |
| R09 | Transporte y tamaño | El payload excede límites, omite filas silenciosamente o usa ruta local como prueba remota |
| R10 | Falsos positivos | `attestation=NONE` se presenta como ejecución atestada |
| R11 | Regresión WEB-001 | La salida declara evolución pese a OP14 PASS→FAIL |
| R12 | Continuidad | El cambio crea pipeline paralelo, nueva tabla, salto de pasos, auto-merge o promoción |
| R13 | Aislamiento de productor/revisor | Se usa el self-verdict del productor como autoridad independiente |

## Resultado del readback de los runs guardados WEB-001

Evidencia de [CI R17 #41214802660](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/41214802660):
- `OP02_OUTPUT_VALID`: FAIL→PASS (mejora).
- `OP01,OP03,OP04,OP05,OP06,OP07,OP08,OP09`: PASS→PASS (8 preservados).
- `OP10,OP11,OP12,OP13`: FAIL→FAIL (4 sin mejora).
- `OP14_DERIVED_OWNER_DECLARED_RULE_SEARCH`: PASS→FAIL (**1 regresión**).
- Ambos registros `attestation=NONE`; condiciones textuales registradas coinciden. NO es nuevo E2E atestado.
- **Dictamen para el caso:** NO APTO para afirmar evolución. No confundir CI de reporte PASS con Group2 PASS.

## Formato exigido de veredicto

`revisor | HEAD probado | R01..R13 PASS/FAIL/NO_VERIFICADO | primera falla | evidencia de prueba propia | clasificación de alcance | riesgo | acción correctiva | dictamen PR | dictamen funcional WEB-001 | decisión de merge`.

**Bloquear cierre** cuando una prueba material no tiene evidencia propia o cuando un destino solo está anclado textualmente. El revisor debe emitir su propio juicio sin ejecutar cambios sobre los perfiles.

## Pendientes que este PR deliberadamente no resuelve

- `WEB-001.case.json` sigue sin bindings oficiales de destino; la tabla solo ofrece candidatos por líneas fuente.
- No existe un catálogo interno de pasos canónicos por perfil certificado para promover cada ancla.
- No se ejecutaron nuevas corridas atestadas del caso original/evolucionado ni juez semántico independiente.
- PR #3412 (amend candidate) sigue siendo otro alcance.

**Prueba de finalización:** las 13 comprobaciones ejecutadas por revisor independiente, exact HEAD verificado, evidencia GitHub + Supabase y veredicto separado para el PR y WEB-001. Este documento no es un certificado de revisión.
