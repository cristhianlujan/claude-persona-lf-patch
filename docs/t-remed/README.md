# T-REMED: cierre de brechas de Input Governance

Todo se **deriva con funciones** (sin tablas nuevas, sin datos fijos). Esquema: `programacion`.
Unidad de brecha = (pantalla x familia). Estado base: `fn_input_governance_bootstrap_classify_v2_cached_v2` (COMPLETE/PARTIAL/MISSING/NOT_APPLICABLE).

## Flujo
1. **Global derivado**: reglas VIGENTE usadas por >=25% de pantallas (USAGE) o declaradas `es_transversal` que pasan el juez de alcance (DECLARED).
2. **Completar** (L2) y **promover** (L3): solo lo que aprueba el juez; todo cambio queda en `t_remed_change_log` y es reversible.
3. **Recomendar**: de pantallas parecidas del **mismo canal** (app shell), para decision humana.
4. **Resto**: dato humano de la pantalla. Si el juez no aprueba, viaja manual.

Estado por pantalla y familia: `select * from programacion.fn_t_remed_screen_status_v1(<pantalla_id>);` -> GUARANTEED / RECOMMENDED / HUMAN_DATA_NEEDED / NOT_APPLICABLE.

## Catalogo (todas leen salvo las marcadas "escribe")
| Funcion | Que hace | Escribe |
|---|---|---|
| fn_t_remed_global_rules_v1 | Nivel global derivado | no |
| fn_t_remed_scope_judge_v1 | Juez de alcance para reglas transversales | no |
| fn_t_remed_effective_rules_v1 / effective_links_v1 | Reglas/vinculos efectivos de una pantalla (propios + heredados) | no |
| fn_t_remed_inherited_rules_v1 | Herencia desde pantallas similares | no |
| fn_t_remed_rule_promotion_verdicts_v1 | Juez de promocion de reglas | no |
| fn_t_remed_promote_v1 (lote) / promote_v3 / complete_v3 / run_v3 | Aplican cambios aprobados por juez, con log | **si** |
| fn_t_remed_revert_promotion_v1 / undo_v3 | Reversion de un cambio logueado | **si** |
| fn_t_remed_recommend_v1 / recommend_queue_v1 | Recomendaciones y cola para decision humana | no |
| fn_t_remed_open_decisions_v1 / pending_deps_v1 | Decisiones abiertas y dependencias en reglas | no |
| fn_t_remed_screen_status_v1 / queue_v1 | Estado por pantalla y cola de trabajo | no |
| fn_t_remed_reconcile_v3 / target_of_key_v3 / raw_refs_v1 | Capa 1: reconciliacion de referencias | no |
| fn_t_remed_layer1_selftest_v3 / property_test_v3 / test_v3 | Pruebas capa 1 (fixtures con rollback) | simulado |
| fn_t_remed_selftest_v1 | Invariantes globales | no |

## Verificar
`select * from programacion.fn_t_remed_selftest_v1();` -> todas las filas con `passed = true`.

## Nombres y versiones
- Formato `fn_t_remed_<verbo>_v<N>`. Version nueva = contrato incompatible; una v1 ya aplicada puede redefinirse en su lugar solo si el contrato no cambia (queda anotado abajo).
- Todo comentario de funcion sigue `LF_METADATA_V1` (PURPOSE/INPUTS/OUTPUT/EFFECTS/FAMILY/USAGE).
- Funciones heredadas sin descripcion previa llevan "SIN DESCRIPCION PREVIA": `complete_v1`, `promote_v1(pantalla)`, `pt_make_v3`, `raw_refs_v1`, `reconcile_v1`. Candidatas a retiro (v1 conviven con v3) o a documentar.

## Cambios in-place de funciones v1
- `recommend_v1`: restringida al mismo app shell (20261010220000).
- `global_rules_v1`: usa el juez de alcance (20261010240000).
