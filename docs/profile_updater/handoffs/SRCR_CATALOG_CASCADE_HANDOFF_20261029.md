# Handoff: systemic_root_cause_repair_lf — búsqueda por niveles, cierre "exploré todo" y triaje

Fecha: 2026-10-29. Estado: CANDIDATO local, NO publicado en `profiles/**`. Este PR es borrador y solo trae el parche y esta nota.

## Qué contiene
`SRCR_CATALOG_CASCADE_CANDIDATE_20261029.patch` (aplica con `patch -p1` dentro de `profiles/systemic_root_cause_repair_lf`). Toca 6 archivos:
- `SKILL.md`: (a) triaje al inicio (actualizar perfil -> devolver al Router con `ACTUALIZACION_PERFIL_LF` por `GOVERNED_PROFILE_UPDATE_DISPATCH_V1`; ejecutar perfil -> `EJECUCION_PERFIL_LF`; incidente -> sigue el método); (b) paso 2 de la cascada con búsqueda por niveles N1..N6; (c) texto de cierre "exploré todo lo alcanzable y no encontré evidencia".
- `validators/producer_depth.py`: una cascada con las 5 clases cubiertas ya no se rechaza; exige `cascade.search_record` (clase, fuente, ubicación, resultado). Declarar una clase `NO_SOURCE_ACCESSIBLE` exige `cascade.catalog_checked` con entradas N1, N2, N3 y N4.
- `validators/terminality_gate_v1.py`: sub-estado `evidence_state` = `EXPLORED_NO_EVIDENCE_FOUND` | `SEARCH_INCOMPLETE`. El valor de `status` NO cambia (sigue `NEEDS_MORE_EVIDENCE`).
- `evals/v05_*`, `evals/v08_*` ajustados; `evals/v09_exhausted_search_cases.py` nuevo.

## Niveles de búsqueda (todos verificados: existen y responden con SELECT)
- N1 vistas listas: `v_lf_fuente_operativa_busqueda` (223), `v_lf_inventario_activo` (223), `v_lf_operation_contract` (65), `v_lf_operation_policy_snapshot` (166), `v_lf_operation_steps_with_contracts` (682), `v_lf_github_reconciliation_queue_v3` (64, todas STALE), `v_lf_deuda_abierta` (40), `v_lf_healthcheck` (1), `v_lf_artifact_destination_registry` (4).
- N2 tablas canónicas: `lf_activos`, `lf_operation_contracts`, `lf_operation_step_contracts`, `lf_operation_judges`, `lf_operation_execution`, `lf_decisiones_gov`, `lf_error_knowledge`, `lf_backlog_errores_operativos`, `lf_deuda_documental`, `lf_patches`, `lf_eventos`.
- N3 resto de la base por descripción (`pg_description`: 63/116 tablas y 41/97 vistas la tienen).
- N4 GitHub (árbol de `main`, luego ramas/PRs). N5 documentos de proyecto y memoria. N6 cierre.
- No legible con el acceso RO: `v_lf_artifact_inventory_status_v3` (permiso denegado sobre `fn_lf_artifact_v3_evidence_valid`).

## Pruebas (reglas, no modelo)
v05 33/33, v08 13/13, v09 7/7, v07r1 terminalidad 10/10. `v07r1_runtime_context_budget_cases.py` ya falla en main (preexistente).

## Corridas con modelo (caso WEB-001, a ciegas, 1 corrida por versión; el caso varía entre corridas)
- exam8: no validó (cascada agotada sin salida válida).
- exam9: validó, NEEDS_MORE_EVIDENCE con registro de las 5 clases; no usó el catálogo (marcó fuentes `NONE`).
- exam10: no validó (17 errores; no armó el andamiaje completo de NEEDS_MORE_EVIDENCE).
- exam11 (con niveles): validó, SYSTEMIC_REPAIR_SPEC; saltó N1 y N5 y ningún validador lo detectó.

## Pendiente (en este orden)
1. Exigir al menos una consulta N1 y una N2 en todo cierre con búsqueda registrada, no solo cuando se declara una clase sin fuente (hoy el orden no se verifica). Con su prueba.
2. Repetir la corrida varias veces por árbol: el mismo perfil dio 9/9 y 6/9, una sola corrida no sirve de evidencia.
3. Decisión abierta: el estado sigue llamándose `NEEDS_MORE_EVIDENCE`. Cambiar el nombre tocaría migraciones y validadores.
4. Para pasar a `profiles/**`: solo por `ACTUALIZACION_PERFIL_LF` (`scripts/lf_profile_update_run.py`); antes hace falta un run operacional candidato ligado al nuevo `profile_tree_sha256` mergeado a main por el Train. No hay nada de eso hecho.
5. Cuando estén aprobadas, lo ideal es que N1/N2 salgan de una vista única en la base (migración por el Train, nombre `lf_...`); hoy están escritos en el SKILL.md.
6. Pendientes ajenos: 2 ramas remotas sin borrar (`lf/profile-op-case-product-director-hmo-pricing`, `lf/profile-op-case-ci-parity-001`), caso `CI-PARITY-001` sin correr, alias SUPER_ADMIN, 7 checks semánticos.

## No se hizo
Nada escrito en la base, nada en `profiles/**`, sin changeset manifest (borrador, sin label `ready-to-merge`).
