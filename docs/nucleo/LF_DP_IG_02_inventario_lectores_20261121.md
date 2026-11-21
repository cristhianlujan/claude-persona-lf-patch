# DP-IG-02 — Lecturas de reglas legadas por IG y perfiles

Fecha: 2026-11-21. Diagnóstico exclusivamente documental; no se redirige ningún consumidor. Fuente Git inspeccionada: `72d2aa6e43ab11f4be358ba6a9fd9eff080acdd8`. Base de creación propuesta: `72d2aa6e43ab11f4be358ba6a9fd9eff080acdd8`. Base de datos LF_SUPABASE_SANDBOX (PG 17.6); rol supabase_read_only_user. DP-IG-01 cerrado por #4553, merge 8a332b67e7663ac22c7c0cb5e90f553911f18f0f y Train 44922338844. Criterio DP-IG-02 precisado por el dueño en este ciclo: identificar lectores de lf_ops.reglas, prevention_rules y cobertura; separar datos de controles. No se redefine D8 ni otros criterios. Cierre sujeto a PASE, Train, readback del documento y nueva ejecución SQL.

## 1. Alcance y método

- Catálogo de funciones desplegadas, incluyendo firma y MD5 de pg_get_functiondef; no se ejecuta ningún consumidor. Búsqueda textual acotada a nombres de relaciones exactos (también alternativas no calificadas). Comprueba FROM/JOIN y DML por separado. Las apariciones textuales, incluida una sentencia en una cadena SQL, son **candidatas** y no garantizan alcance o ejecución; pueden existir comentarios, SQL dinámico, alias, joins no reconocidos, referencias externas, funciones dispatch indirectas, otras bases o schemas. No equivale a un parser AST, traza ni prueba de ausencia universal. Se distinguen lecturas de la tabla de negocio, controles EKB y cobertura. Las firmas (incluidas sobrecargas) se conservan.
- Vistas: dependencias de relaciones registradas en pg_depend/pg_rewrite, evidencia estructural directa (no recorrido transitivo de todas las vistas). Las funciones invocadas por una vista se inspeccionan adicionalmente en su definición.
- Alcance nominal focal IG, perfiles, contratos de pantalla, Router y T_REMED como fronteras; inventario ampliado adjunto de candidatos no focales, no se atribuyen a IG/perfiles por mera coincidencia. DATO=fila, vínculo, contrato o contexto consumido para contenido; CONTROL=procedencia, hash, readiness, autorización, validación o EKB; MIXTA=datos y control, mantener ambos aspectos separados. Etiquetas [focal] apoyadas en cuerpos revisados; [orientativa] es clasificación inicial por nombre y relaciones, no veredicto semántico por función; MIXTA/POR CONFIRMAR evita certificar roles ambiguos. DML textual no significa efecto autorizado ni prueba de que la función sea escritora de las reglas.
- No se llama ni cambia IG, perfil, Router, skill, lectores, escritores, gates, tablas, permisos, reglas ni producción; no se crea migración. Sin decisiones de arquitectura/efecto y sin asumir D8. Regla de A4: no añadir lectores directos en código operativo. Documento no es un nuevo lector.

## 2. Resultados medidos (corte)

| Universo | Firmas con referencias | FROM/JOIN textual | DML textual | Solo referencias |
|---|---:|---:|---:|---:|
| Todos los schemas de aplicación inspeccionados | 220 | 202 | 22 | 12 |
| Alcance nominal focal y fronteras | 176 | 166 | 17 | 5 |

Intersección lectura/DML permitida en conteos. En foco y fronteras, 71 firmas llevan FROM/JOIN a lf_ops.reglas explícitamente; no son todas lectoras de producto ni equivalen a una cantidad de rutas operativas comprobadas. 12 vistas con dependencia directa; 3 funciones con referencia textual a prevention_rules (incluye lector transversal de conocimiento fuera de IG directo). Inventario global de la consulta nominal anterior con filtros diferentes (212 candidatos y 105 referencias a lf_ops.reglas) no se suma ni reemplaza las cifras de este inventario ampliado por nombres no calificados. Clasificación focal: {"DATO [focal]":5,"CONTROL [orientativa]":112,"CONTROL [focal]":8,"REF TEXTUAL; no lectura demostrada":5,"MIXTA/POR CONFIRMAR [orientativa]":24,"DATO [orientativa]":8,"MIXTA [focal]":9,"NO LECTURA DETECTADA; DML":5}.
Conteos reales: {"lf":586,"saly":14,"core_lf":10,"core_saly":14,"prevention":280,"sources":12,"members":0,"reuse":17}. 586/10 LF y 14/14 SALY legadas/núcleo; prevention_rules corresponde a transversal, no a la tabla de negocio. Cobertura: 12 fuentes, 0 miembros y 17 entradas del mapa histórico. No se interpreta cero miembros como ausencia de cobertura.

## 3. Rutas y separación de responsabilidades comprobadas en fuente

| Ruta/familia | Clasificación focal | Evidencia exacta / límite |
|---|---|---|
| Perfil Product channel, step45: public.lf_profile_execution_channel_context_v1 → lf_ops.reglas_pantallas JOIN lf_ops.reglas | DATO | Selecciona código, título, estado ordenados, cuenta categorías; también llama lf_ops.fn_screen_contract_v1 para cantidad efectiva. Lee por pantalla; no depende necesariamente de skill IG, ni prueba que todo perfil lo ejecute. MD5 9302760ee29525f02832c628eed397d7. |
| lf_ops.fn_screen_contract_v1 → programacion.fn_input_effective_rule_links_v1 | DATO | Contrato de pantalla; joins legados; inventariar también contrato B2B login. |
| IG: fn_input_effective_rule_links_v1 → lf_ops.reglas_pantallas/lf_ops.reglas + fn_input_declared_rule_links_v1 + fn_t_remed_global_rules_v1 | DATO | Devuelve LEGACY_EXPLICIT, DECLARATIVE_APPLICABILITY_V1 y DERIVED_GLOBAL. La función declarativa usa regla VIGENTE, valor_config.applicability_v1 y selector de contexto. No sustituir vínculos ni umbrales de herencia por decisión implícita. |
| IG: fn_input_screen_canonical_graph, fn_input_governance_semantic_packet_core_v1, probes de campo/semánticos | MIXTA | Grafo/fuente de datos y comprobaciones de atributos; las probes son controles, no reglas nuevas. La presencia de un campo no prueba que el control pase. |
| IG: fn_input_context_manifest / known_current_v1 | MIXTA | Lee universe_rule_id (story_ready_rule, family_count, precedencia, no_invention, readback_required) y assessments; genera estados/hallazgos de preparación. No tratar la regla-universo como regla ordinaria. |
| IG: fn_guard_input_family_assessment_insert, fn_guard_input_readiness_run | CONTROL | Comprueban universe_rule_id, lineage/run/sucesor y condiciones de assessments. No redirigirlos junto con lecturas de datos. |
| IG: fn_input_resolve_source_ref_v510 → RULE / SCREEN_RULE_SET / EKB_PREVENTION_SET | CONTROL | Resuelve fila de regla o set pantalla/reglas para observación, y transversal.prevention_rules por códigos con cardinalidad obligatoria. Hash y procedencia. No mezclar prevención con regla de producto. |
| IG: fn_input_governance_ekb_checkpoint → public.lf_prevention_rules → transversal.prevention_rules | CONTROL | EKB activa, severidad y prevención por códigos; devuelve recibo y bloqueos no atendidos. public.lf_prevention_rules es una vista directa del repositorio transversal. Lector de conocimiento transversal adicional: transversal.programming_agent_knowledge_privileged_v1. |
| Skill IG opcional: lf_skill_h_input_governance_context_pack_v1 → fn_lf_profile_input_governance_resolve_v1 → fn_input_governance_execute | CONTROL / indirecta | DP-IG-01; resolver no contiene FROM/JOIN directo a lf_ops.reglas; ejecutor reúne readiness y assessments, usa EKB y manifest. No significa ausencia de consumo indirecto. |
| Transporte Edge: lf-profiles-governance-caller-v1 → input_readiness_context_pack_runtime_v1 / ticket; input-governance-agent-v1 → RPC fn_input_governance_execute; curator/validator | CONTROL / indirecta | Ticket/RPC/curación y validación. No se ejecutaron Edge ni se certificó paridad desplegada; archivos Git identificados abajo. |
| Cobertura: public.v_lf_input_family_coverage_by_screen_v1 → fuentes/miembros / lf_ops.reglas/links → catálogo / reuse | MIXTA | Vista verifica hash actual, estado VIGENTE, transversalidad, alcance y rutas de evidencia LEGACY. Invoca fn_input_effective_rule_links_v1, fn_t_remed_global_rules_v1, fn_t_remed_inherited_rules_v1, fn_t_remed_effective_rules_v1 y fn_t_remed_scope_judge_v1. family_closure_verified=false e implementation_authorized=false. No autoriza implementación. |
| Step45: public.lf_profile_execution_context_admission_v1 → lf_input_family_catalog_context_for_run_v1 → lf_input_family_catalog_context_v1 → vista | MIXTA | Contexto de cobertura; no copia texto como nueva regla. |
| Step50/60: public.lf_profile_native_bridge_record_output_v1 / lf_profile_execution_canonical_read_judge_v1 → lf_input_family_claims_gate_for_run_v1 → lf_input_family_reuse_claims_gate_v1 → vista | CONTROL | Valida reclamaciones y cobertura. No activar/desactivar el gate. |
| public.lf_input_family_reuse_before_propose_v1 → vista | MIXTA | Lee referencia de cobertura y vigencia, no crea vínculo; la cadena input_family_reuse_map_v1/run/956 en su cuerpo es referencia histórica y no FROM/JOIN al mapa. |
| Step50 effect before/after/guard → lf_profile_step50_rule_snapshot_v1 → lf_ops.reglas | CONTROL | Snapshot fuera de timestamps, verificación pantalla-regla, hash pre/post y recibo real. Conservado aunque se refactorice lectura de producto en otro ciclo; sin decisión D8. |
| T_REMED / fn_input_governance_policy_autobind_v1 | MIXTA y frontera DML | Funciones de alcance heredado y reconciliación; lectura no siempre separable de escritura en el mismo cuerpo. No ejecutar ni redirigir autores. |

Fuentes Git de la revisión indicada:
- `supabase/migrations/20261119001500_lf_product_context_canonical_rules_lazy_digest_v1.sql` blob 084bdf641b5e0867954aede14f45aeb2957133ed, líneas 185–220, 255. `services/profile_runtime_api/scripts/hetzner_queue_worker.py` blob af4777616aab6c1c0eefaab380c3d50ad780c233 línea 673: llama función de contexto.
- `docs/input-governance/lf_ig_family_reference_catalog_v1_20261114.md` blob 7fd2944ea45bad676396d6c42d93ee177f47200d, líneas 3, 37–46; `supabase/migrations/20261114224412_lf_input_family_inheritance_reference_v1.sql` blob 5a87b1ad43c3dcc1ba2e3b54d995c3c38f0b014b, líneas 207–226, 244–335, 495–514, 805, 1003.
- `supabase/functions/input-governance-agent-v1/index.ts` blob 61ac4022000cbe9685b7bd728d522b2148affff9, líneas 95, 120, 128, 141, 201; `supabase/functions/lf-profiles-governance-caller-v1/caller.ts` blob e3de51c339b968b1aadebdaca1637c157b6fef46, líneas 15–16, 373–393, 647.
- Rutas históricas localizadas en búsqueda Git, no prueba de activación: `supabase/migrations/20261010144706_t_remed_inheritance_wiring_v1.sql`; `supabase/migrations/20261116102000_lf_e21_step50_verified_real_effect_v1.sql`; `supabase/migrations/20261010150138_t_remed_generic_screen_contract_v1.sql`; `supabase/migrations/20260824154643_lf_input_governance_execution_dispatcher_v1.sql`; `supabase/migrations/20261003001000_ig_cv_m2_2_empty_collection_semantics_v1.sql`. Los cuerpos PG actuales, no la migración histórica aislada, sustentan rutas.

## 4. Dependencias de vistas (catálogo PG, directas)

| Vista | Relaciones directas del conjunto | MD5 pg_get_viewdef pretty | Clasificación |
|---|---|---|---|
| `lf_ops.v_b2b_rel_screen_rule` | lf_ops.reglas, lf_ops.reglas_pantallas | `2a0e6bfb34dd8c8b09b9b803180c2907` | DATO — frontera de compatibilidad/relación |
| `lf_ops.v_legado_alcance_decision` | lf_ops.reglas, lf_ops.reglas_pantallas | `40b269a63b20b21135db36a7baa6fa69` | CONTROL/DIAGNÓSTICO — frontera |
| `lf_ops.v_nucleo_regla_clasificacion` | lf_ops.reglas | `163368019972d4cc506bad2182c70bbb` | CONTROL/DIAGNÓSTICO — frontera |
| `lf_ops.v_reglas_compat_v1` | lf_ops.reglas | `b30c7bcf42644ee224f290566aec1e07` | DATO — frontera de compatibilidad/relación |
| `lf_ops.v_reglas_historial` | lf_ops.reglas | `814aea68202c64de357a8e8df8ee5640` | CONTROL/DIAGNÓSTICO — frontera |
| `private.v_lf_ig_human_decision_source_current_v1` | programacion.input_readiness_runs | `036d4cc127a6f4f147cd95e1902ad22c` | CONTROL — readiness/procedencia |
| `programacion.v_ig_m105_cohort_evidence_v1` | programacion.input_family_assessments, programacion.input_readiness_runs | `7e51c1b46b5771de6b794c228657c321` | CONTROL — readiness/procedencia |
| `programacion.v_ig_m105_cp2_sample_readback_v1` | programacion.input_family_assessments, programacion.input_readiness_runs | `3d01041004d5cbb4778bea6068285c67` | CONTROL — readiness/procedencia |
| `programacion.v_ig_m105_cp2_verdict_v1` | programacion.input_family_assessments | `6a007bda604874144f9e730bf772364a` | CONTROL — readiness/procedencia |
| `programacion.v_input_run_manifest` | programacion.input_readiness_runs | `da772ba32da842c92f1eecaff296b727` | CONTROL — readiness/procedencia |
| `public.lf_prevention_rules` | transversal.prevention_rules | `b512d2f97376d49bdc5cef13889a9748` | CONTROL — EKB |
| `public.v_lf_input_family_coverage_by_screen_v1` | lf_ops.reglas, lf_ops.reglas_pantallas, programacion.input_family_inheritable_members_v1, programacion.input_family_inheritable_sources_v1 | `6334e15a5e9bb6ef418df6b06ba1e40d` | MIXTA — cobertura/control |

## 5. Inventario de funciones — foco nominal y fronteras (firmas exactas)

| Firma SQL | Tipo / grado de evidencia | FROM/JOIN textual | DML textual | MD5 definición |
|---|---|---|---|---|
| `lf_ops.fn_b2b_backoffice_login_contract(p_app_shell_code text, p_module_code text, p_screen_code text)` | DATO [focal] | lf_ops.reglas, lf_ops.reglas_pantallas | — | `bc97c870e7418fd69056aa1f951a4c2f` |
| `lf_ops.fn_screen_contract_v1(p_app_shell_code text, p_module_code text, p_screen_code text)` | DATO [focal] | lf_ops.reglas, lf_ops.reglas_pantallas | — | `4407d40bb6d6d913b4d9ee72399d6f55` |
| `programacion.fn_engineering_ig_validator_assertion_fail_probe_v1(p_pantalla_id integer)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `eb79a061285c29d9ad43f453a4ed69b0` |
| `programacion.fn_engineering_ig_validator_mismatch_probe_v1(p_pantalla_id integer)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `5214e9212dbd6ff5ccbd1b9934b0b5ea` |
| `programacion.fn_engineering_ig_validator_mutation_campaign_v1(p_pantalla_id integer)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `94eb1cfe184e3a0d0dadcac76c7d6646` |
| `programacion.fn_engineering_ig_validator_mutation_case_v2(p_case integer, p_pantalla_id integer)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `d6bc9625a6e5f13f2c71de759e60959a` |
| `programacion.fn_guard_input_family_assessment_insert()` | CONTROL [focal] | lf_ops.reglas, programacion.input_readiness_runs | — | `7fec79c7046fdf4de8d538488c696b26` |
| `programacion.fn_guard_input_family_assessment_update()` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `21dae3fe374e619ff202190399bc9b86` |
| `programacion.fn_guard_input_family_execution_insert()` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `886f5bb68c96974790b742889e964377` |
| `programacion.fn_guard_input_family_execution_update()` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `33062dc8ab57845a8db78bc9a4182b4c` |
| `programacion.fn_guard_input_family_semantic_depth()` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `159d1888363afc74298d8e3d89e88914` |
| `programacion.fn_guard_input_family_semantic_depth_v510()` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `9c605193666ec694e0ca6a550fe7e48e` |
| `programacion.fn_guard_input_gap_proposal_insert_v512()` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `7853857c91c85d61f9473391a39d2384` |
| `programacion.fn_guard_input_gap_proposal_update_v512()` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `6e908585ee54295481a7acd7538db5ee` |
| `programacion.fn_guard_input_governance_continuation_currentness_v1()` | REF TEXTUAL; no lectura demostrada | — | — | `74b1c9b4e1fc35a226fa1092dce341ff` |
| `programacion.fn_guard_input_na_positive_authority_v512()` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `916176f62880f6987fb99d4703b32a2a` |
| `programacion.fn_guard_input_readiness_run()` | CONTROL [focal] | lf_ops.reglas, programacion.input_family_assessments, programacion.input_readiness_runs | — | `31497197ab480066e4cfc858a507f89b` |
| `programacion.fn_guard_input_stage_earliest_boundary()` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `ce4ac1c826648c4a981a1dc65da216cb` |
| `programacion.fn_guard_input_validator_semantic_coherence_v512()` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `6816ad1a08a43c4b073a2c660ebbf067` |
| `programacion.fn_ig_causal_lineage_receipts_emit_v1(p_run_id bigint)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `bfbbcea400cfc34ff56dfabd638a5d91` |
| `programacion.fn_ig_evo_r2_r6_diagnostics_v1(p_pantalla_id integer, p_run_id bigint)` | CONTROL [orientativa] | lf_ops.reglas, programacion.input_family_assessments, programacion.input_readiness_runs | — | `d0502a31a7c99ff29b0159a65c2f493c` |
| `programacion.fn_ig_evo_rule_graph_inventory_v1(p_pantalla_id integer, p_regla_id integer, p_max_hops integer)` | CONTROL [orientativa] | lf_ops.reglas | — | `3acbd3d90eb95793ee753495a8950d55` |
| `programacion.fn_ig_graph_receipt_consumer_readback_v1(p_run_id bigint, p_graph_sha256 text, p_source_head_sha text, p_producer_execution_id text, p_ledger_execution_id text, p_orchestrator_execution_id text)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `a4827c603cf1fed6e046a59619adb30b` |
| `programacion.fn_ig_graph_receipt_emit_per_run_v1(p_run_id bigint, p_producer_execution_id text, p_ledger_execution_id text, p_source_head_sha text, p_consumed_graph_sha256 text)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `34c9e4cb5398e8524d195bb0eb2a2304` |
| `programacion.fn_ig_graph_receipt_on_validator_completed_v1(p_run_id bigint, p_validator_identity text, p_handoff_receipt_id bigint)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `179b6ad93d043ea5eb670e989917dc8d` |
| `programacion.fn_ig_m105_cp2_closure_proof_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `cc7ac7c9261d791a73dc9080bd1da29b` |
| `programacion.fn_ig_m107_bundle_from_manifest_v1(p_run_id bigint, p_manifest jsonb)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `dc33a1a7bf1ba0f6692fc5b35b8ff7ee` |
| `programacion.fn_ig_m107_currentness_from_manifest_v1(p_run_id bigint, p_read_manifest jsonb)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `71fa52c4a5afe16d0e56e90a7398985a` |
| `programacion.fn_ig_m107_trusted_run_data_v1(p_run_id bigint)` | CONTROL [orientativa] | lf_ops.reglas, programacion.input_family_assessments, programacion.input_readiness_runs | — | `d04eb1848968e98041b7bad1d8ca2423` |
| `programacion.fn_ig_m98_candidate_field_gate_v2(p_id uuid)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `2a85a2a06bd5c9d9f0754556a0c2ea13` |
| `programacion.fn_ig_m98_engineering_assurance_v7(p_run bigint, p_screen integer, p_mutation uuid, p_divergence uuid, p_bundle text, p_field uuid)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `aa8845e51970f6bb8c8d1bd2b1900a69` |
| `programacion.fn_ig_m98_gate_readback_v2(p_run bigint, p_screen integer, p_mutation uuid, p_divergence uuid, p_bundle text, p_field uuid)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `6d63361853e0a40b8143cf868b8ddce2` |
| `programacion.fn_ig_release_criteria_controls_v1(p_family_run_id bigint, p_false_pass_suite_run_id uuid, p_divergence_suite_run_id uuid, p_bundle_sha256 text)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `b6f62401b55fd58319dabc09bc7c404e` |
| `programacion.fn_ig_spec_traversal_emit_per_run_v1(p_run_id bigint, p_producer_execution_id text, p_ledger_execution_id text, p_source_head_sha text)` | REF TEXTUAL; no lectura demostrada | — | — | `30b3ee9fb25327f0b11102efda686400` |
| `programacion.fn_ig_spec_traversal_orchestrate_per_run_v1(p_run_id bigint)` | REF TEXTUAL; no lectura demostrada | — | — | `1a41a12bd6720555b998e17aa8bea6b7` |
| `programacion.fn_ig_spec_traversal_preview_v1(p_run_id bigint)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `38b0737f66592a6b85c974972a542c3d` |
| `programacion.fn_ig_timing_receipts_emit_v1(p_run_id bigint, p_observation jsonb, p_source_graph_sha256 text)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `f19a77628b26a1e905574fcb5ee8d456` |
| `programacion.fn_ig_validator_execution_metrics_v1(p_run_id bigint)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `aefe9aa5911642f47f626fd04f923e8d` |
| `programacion.fn_ig_validator_timing_receipt_emit_v1(p_run_id bigint)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `ab0d7c9722f85023311c2a1395155ade` |
| `programacion.fn_ig_visual_image_requirement_readback_v1(p_screen_id integer, p_purpose text)` | CONTROL [orientativa] | lf_ops.reglas | — | `e2ae5ca87265227933cd0cae3b8ad64a` |
| `programacion.fn_input_actionable_remediation_summary_v1(p_run_id bigint)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas, programacion.input_family_assessments, programacion.input_readiness_runs | — | `fb9bab72f05b34e778caa1870cd16cc1` |
| `programacion.fn_input_api_contract_resolution(p_pantalla_id integer)` | DATO [orientativa] | lf_ops.reglas | — | `bb3ba940ed353fac83a116228b1997f2` |
| `programacion.fn_input_archive_source_observation_v1(p_run_id bigint, p_ref jsonb, p_source_execution_id text, p_ledger_execution_id text, p_source_head_sha text)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `7821e84e45ab4c54bff25d9a5f90807e` |
| `programacion.fn_input_auth006_build_assertions(p_run_id bigint, p_seed_run_id bigint, p_family_code text)` | CONTROL [orientativa] | programacion.input_family_assessments | — | `fcbe577977533315efa654e37f6fedaf` |
| `programacion.fn_input_build_source_manifest_safe_v1(p_run_id bigint)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `cbe9282a0fe72628cc3e0b707973fd02` |
| `programacion.fn_input_context_manifest(p_run_id bigint)` | MIXTA [focal] | lf_ops.reglas, programacion.input_family_assessments, programacion.input_readiness_runs | — | `827b67d5b8ba7a061121570d3b8c7e6b` |
| `programacion.fn_input_context_manifest_known_current_v1(p_run_id bigint, p_run_current boolean)` | MIXTA [focal] | lf_ops.reglas, programacion.input_family_assessments, programacion.input_readiness_runs | — | `3fd56083ad2b633fd794f9ffec36f9c4` |
| `programacion.fn_input_curator_compose_before_insert_v1()` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `54531263418fb9d9ba491fd1e4d702f7` |
| `programacion.fn_input_declared_rule_links_v1(p_pantalla_id integer, p_consumer text)` | DATO [focal] | lf_ops.reglas | — | `990226616c7f48fc82346799e54c2bdf` |
| `programacion.fn_input_design_binding_graph(p_pantalla_id integer)` | DATO [orientativa] | lf_ops.reglas | — | `1556231d097a941fabc2d50f3c9ec2a4` |
| `programacion.fn_input_design_system_resolution_v1(p_pantalla_id integer)` | DATO [orientativa] | lf_ops.reglas | — | `4b2edf413f6bd225d89a9e4efc1885a6` |
| `programacion.fn_input_deterministic_assess(p_subject jsonb, p_family text, p_graph jsonb, p_contract jsonb)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `cdabc68cdea71c3a8ce7c74b93ba8116` |
| `programacion.fn_input_effective_rule_links_v1(p_pantalla_id integer, p_consumer text)` | DATO [focal] | lf_ops.reglas, lf_ops.reglas_pantallas | — | `156247a925d74c6f4accd7a6d2508489` |
| `programacion.fn_input_evaluate_assertion(p_run_id bigint, p_family_code text, p_assertion jsonb)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `7eabfac8ab216697b1c1fff620f5a25c` |
| `programacion.fn_input_evaluation_outcome_summary(p_run_id bigint)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `353e2df7a18c1b745f71e11c6cb5c12d` |
| `programacion.fn_input_evaluation_outcome_summary_known_current_v1(p_run_id bigint, p_run_current boolean)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `5918f38ce137a80032d553ff41b31608` |
| `programacion.fn_input_explain_family_assessment(p_run_id bigint, p_family_code text)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `a93de1e2f66613f79cf55ae8e4863be3` |
| `programacion.fn_input_freshness_delta(p_run_id bigint)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `af7d92b6458726914d17e3fc00008358` |
| `programacion.fn_input_golden_case_run_v1(p_test_code text)` | CONTROL [orientativa] | programacion.input_family_assessments | — | `5221e2a28f99e9c2680625464f76eceb` |
| `programacion.fn_input_gov_gold_b_consume_review_v1(p_run_id bigint, p_family_code text, p_case_manifest jsonb, p_receipt_id uuid)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `9c3bc66c6d3b8ff60a877c5add56d15e` |
| `programacion.fn_input_gov_gold_b_prepare_review_v1(p_run_id bigint, p_family_code text, p_case_manifest jsonb)` | CONTROL [orientativa] | programacion.input_family_assessments | — | `59fb4e900d1119c89b8073cac11b4363` |
| `programacion.fn_input_governance_bootstrap_assertions_v1(p_run_id bigint, p_family_code text)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `e6ac92cffa1a25b929a6004e9c5a7f65` |
| `programacion.fn_input_governance_bootstrap_classify_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `edbc58dcba5134301ee4f710a90717f9` |
| `programacion.fn_input_governance_bootstrap_classify_v1_cached_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `f00ed3bbf1259932ce19f6705506ee54` |
| `programacion.fn_input_governance_bootstrap_classify_v1_cached_v2(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `2f118e45423da99ea471ce659c9b9789` |
| `programacion.fn_input_governance_bootstrap_classify_v1_ctx(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `faf3aec3fc853b2af73a6bc7a390ade7` |
| `programacion.fn_input_governance_bootstrap_materialize_v1(p_pantalla_id integer, p_consumer text, p_curator_identity text)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas, programacion.input_family_assessments, programacion.input_readiness_runs | programacion.input_family_assessments, programacion.input_readiness_runs | `764ae4af17551975341330337461f0d4` |
| `programacion.fn_input_governance_bootstrap_materialize_v2(p_pantalla_id integer, p_consumer text, p_curator_identity text)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas, programacion.input_family_assessments, programacion.input_readiness_runs | programacion.input_family_assessments, programacion.input_readiness_runs | `12c219cd87535b99c28cd38f083ad72e` |
| `programacion.fn_input_governance_bootstrap_validate_v1(p_run_id bigint, p_validator_identity text)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | programacion.input_family_assessments, programacion.input_readiness_runs | `8eb7ac372e67a9a7bf02d763641cb3fb` |
| `programacion.fn_input_governance_continuation_currentness_v1(p_run_id bigint)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `6f6933102b9a38a2e2c52e7858c1360b` |
| `programacion.fn_input_governance_curator_handoff_receipt_v1(p_run_id bigint, p_expected_curator_identity text)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `55addbfb8747a3eebde5f523ee0928ac` |
| `programacion.fn_input_governance_curator_materialize_v1(p_pantalla_id integer, p_consumer text, p_curator_identity text, p_force_selftest boolean)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `dabf6267aea4f1c9e61d37acc2f4c4d6` |
| `programacion.fn_input_governance_curator_plan_v1(p_pantalla_id integer, p_force_selftest boolean, p_completed_run_id bigint)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `9db77a132cc5590327d50057c3c3041c` |
| `programacion.fn_input_governance_curator_rebind_v1(p_pantalla_id integer, p_consumer text, p_curator_identity text, p_force_selftest boolean)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | programacion.input_family_assessments, programacion.input_readiness_runs | `89747931232cf7ba0093e9d26b730d49` |
| `programacion.fn_input_governance_direct_step_v1(p_pantalla_id integer, p_consumer text)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `e311f207874c898a7bc9d04da4bb8429` |
| `programacion.fn_input_governance_ekb_checkpoint(p_phase text, p_pantalla_id integer, p_run_id bigint)` | CONTROL [focal] | public.lf_prevention_rules | — | `c8767ab3b931a84752d5a25ff12ecd4e` |
| `programacion.fn_input_governance_execute(p_pantalla_id integer, p_consumer text)` | MIXTA [focal] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `68a6a5466ed40a06d673eb1cffc24ec2` |
| `programacion.fn_input_governance_field_reference_probe_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint)` | CONTROL [orientativa] | lf_ops.reglas | — | `b7329b48760a04e2346e79f3ad6c7bf6` |
| `programacion.fn_input_governance_field_reference_probe_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)` | CONTROL [orientativa] | lf_ops.reglas | — | `16aac51c9914758cbca6e5c5c922f56d` |
| `programacion.fn_input_governance_field_reference_probe_v1_cached_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)` | CONTROL [orientativa] | lf_ops.reglas | — | `e53910845fbae8e207c72d6146f2f96f` |
| `programacion.fn_input_governance_materialize_gap_proposals_v1(p_run_id bigint)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `9a04278f4a4b7345da88a5ae1d7875e4` |
| `programacion.fn_input_governance_module_health(p_version_id bigint, p_module_code text)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `fe4ac1316712fab01c9f0fafdcc71004` |
| `programacion.fn_input_governance_policy_autobind_v1(p_pantalla_id integer, p_consumer text, p_curator_identity text)` | MIXTA [focal] | lf_ops.reglas, lf_ops.reglas_pantallas | lf_ops.pantallas_politicas_reglas | `5fe00fba24eb29cb93305cef170d33ec` |
| `programacion.fn_input_governance_predecision_crosscheck_v1(p_run_id bigint)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `eaf76030285a49b88522093577b98382` |
| `programacion.fn_input_governance_record_ekb_occurrence(p_classification text, p_error_code text, p_phase text, p_pantalla_id integer, p_run_id bigint, p_evidence text, p_details jsonb)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `b6caa4ca6616e1d3d2179873e307d988` |
| `programacion.fn_input_governance_recurate_source_stale_v1(p_pantalla_id integer, p_consumer text, p_curator_identity text, p_parent_run_id bigint)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas, programacion.input_family_assessments, programacion.input_readiness_runs | programacion.input_family_assessments, programacion.input_readiness_runs | `93e458cdc7cac1b13a2067aba02ceb28` |
| `programacion.fn_input_governance_recurate_v2(p_pantalla_id integer, p_consumer text, p_curator_identity text)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas, programacion.input_family_assessments, programacion.input_readiness_runs | programacion.input_family_assessments, programacion.input_readiness_runs | `9c71982a6cd5ca2b915bca729fb0a9d6` |
| `programacion.fn_input_governance_run_context_packet_v1(p_run_id bigint)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `c0d4e5e8515e79343358fa1d490d0ca6` |
| `programacion.fn_input_governance_safe_autofix_v1(p_run_id bigint)` | CONTROL [orientativa] | lf_ops.reglas, programacion.input_readiness_runs | — | `45bd95f8849a609772ef01f7c4e1c11c` |
| `programacion.fn_input_governance_semantic_packet_core_v1(p_run_id bigint, p_validator_identity text, p_receipt_id bigint)` | MIXTA [focal] | lf_ops.reglas, programacion.input_family_assessments, programacion.input_readiness_runs | — | `004969a2f92a38cdea8f9f3d05a9b739` |
| `programacion.fn_input_governance_semantic_probe_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint)` | CONTROL [orientativa] | lf_ops.reglas | — | `a287fc14c8b70b45ddc72142545ae32e` |
| `programacion.fn_input_governance_semantic_probe_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)` | CONTROL [orientativa] | lf_ops.reglas | — | `c33fb6d411fe1708ae7f1aa0681b7231` |
| `programacion.fn_input_governance_semantic_probe_v1_cached_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)` | CONTROL [orientativa] | lf_ops.reglas | — | `d76ea371cb01ede2079997c79c363d72` |
| `programacion.fn_input_governance_semantic_probe_v3(p_pantalla_id integer, p_family_code text, p_version_id bigint)` | CONTROL [orientativa] | lf_ops.reglas | — | `ef6d48020119217816dd579c6c54da3d` |
| `programacion.fn_input_governance_semantic_probe_v3_cached_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)` | CONTROL [orientativa] | lf_ops.reglas | — | `15722d420ef7160934555c083e1b4309` |
| `programacion.fn_input_governance_semantic_probe_v3_ctx(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)` | CONTROL [orientativa] | lf_ops.reglas | — | `fc93500c9da067ff319a651ae77fabe0` |
| `programacion.fn_input_governance_shadow_evaluate_v1(p_pantalla_id integer, p_version_id bigint)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `10aafca2697d3466fb05fe483eb5b430` |
| `programacion.fn_input_governance_shadow_evaluate_v2(p_pantalla_id integer, p_version_id bigint)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `68243a081521f6dec25b0969b10ca58d` |
| `programacion.fn_input_governance_shadow_family_spec_v2(p_family_code text, p_version_id bigint)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `d75e327ca3e31d4a239b01715cc6e3c1` |
| `programacion.fn_input_governance_shadow_priority_oracle_v2(p_pantalla_id integer, p_family_code text, p_version_id bigint)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `4d95df141035b10255e411b3b7adb472` |
| `programacion.fn_input_governance_shadow_universe_preflight_v1(p_version_id bigint)` | CONTROL [orientativa] | lf_ops.reglas | — | `fbd0806dd9607ad20ea4dd8bc52ecc92` |
| `programacion.fn_input_governance_validate_gap_proposals_v1(p_run_id bigint, p_validator_identity text)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `e0a5485d57b1c74cc5037925d4a9b470` |
| `programacion.fn_input_governance_validate_v2(p_run_id bigint, p_validator_identity text)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | programacion.input_family_assessments, programacion.input_readiness_runs | `d1660d67cfca5da6c6db76ce4ba7a369` |
| `programacion.fn_input_governance_validator_handoff_assert_v1(p_run_id bigint, p_receipt_id bigint)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `513b5ecc95a16b931f14145b60b4a57a` |
| `programacion.fn_input_governance_validator_rebind_v1(p_run_id bigint, p_validator_identity text)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | programacion.input_family_assessments, programacion.input_readiness_runs | `28863392f746749fdb0b664d35116be3` |
| `programacion.fn_input_governance_validator_validate_v1(p_run_id bigint, p_validator_identity text)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `95cf420dd8ce111d957e727253edefa2` |
| `programacion.fn_input_governance_worker_spec(p_pantalla_id integer, p_consumer text)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `38baf13aa638721eb006fce74d0c2291` |
| `programacion.fn_input_governance_worker_spec_known_current_v1(p_pantalla_id integer, p_consumer text, p_current_run_id bigint)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `ddafdd270fb7fae225c0a37fdb67fbe1` |
| `programacion.fn_input_governance_worker_spec_known_no_current_v1(p_pantalla_id integer, p_consumer text, p_no_current_proven boolean)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `51324015cdac976221aa706d57c5fbcc` |
| `programacion.fn_input_internal_remediation_summary(p_run_id bigint)` | CONTROL [orientativa] | programacion.input_family_assessments | — | `e959b6ba36d1df0d8139b6a835e567f0` |
| `programacion.fn_input_internal_remediation_summary_known_current_v1(p_run_id bigint, p_eval jsonb)` | CONTROL [orientativa] | programacion.input_family_assessments | — | `f5b30a37fc8ee7a8614f883432ed666d` |
| `programacion.fn_input_latch_predecessor_invalidation()` | NO LECTURA DETECTADA; DML | — | programacion.input_readiness_runs | `748511c28d9cbca0f895668a1cfc8f2a` |
| `programacion.fn_input_live_compare_run_v1(p_pantalla_id integer)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `9c13c2907b0425854a629c9f755c584d` |
| `programacion.fn_input_owner_decision_assertions(p_new_run_id bigint, p_parent_run_id bigint, p_family_code text)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `cecda8c628c919cd62fac8ba2c8342ca` |
| `programacion.fn_input_policy_autobind_coverage_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.pantallas_politicas_reglas | — | `fdc45c130b1ee3cea3db30293086d4af` |
| `programacion.fn_input_rate_enrichment_assertions(p_new_run_id bigint, p_parent_run_id bigint, p_family_code text)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `61327b42f2238a0c3f21b4e44d307070` |
| `programacion.fn_input_rebind_assertion(p_run_id bigint, p_family_code text, p_assertion jsonb)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `4648a8045098301ccfcfdfe616586a96` |
| `programacion.fn_input_resolve_retrieval_handle(p_run_id bigint, p_handle jsonb)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `dda6c89e3f46c3f89357c4e88ec85cfb` |
| `programacion.fn_input_resolve_source_ref_v510(p_ref jsonb, p_pantalla_id integer, p_version_id bigint)` | CONTROL [focal] | lf_ops.reglas, transversal.prevention_rules | — | `0f43271e2d42cfe461ef1797d2cc9e6c` |
| `programacion.fn_input_run_semantic_revalidation_v1(p_run_id bigint)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `282c443234771147b2f7c4801f7b7a21` |
| `programacion.fn_input_run_source_currentness_v1(p_run_id bigint)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `ba43b8cc06220a2ae079d5d7d6c7710c` |
| `programacion.fn_input_screen_canonical_graph(p_pantalla_id integer, p_version_id bigint)` | MIXTA [focal] | lf_ops.reglas | — | `461d394f47d84351ae9f625618ee276f` |
| `programacion.fn_input_security_capability_profile(p_pantalla_id integer)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `3b569ac8e4f9931a2c08962bd4544514` |
| `programacion.fn_input_security_threat_expected(p_pantalla_id integer)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `849348b54cf9066fe41b0f2d3060929c` |
| `programacion.fn_input_security_threat_expected_v510(p_pantalla_id integer)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `270e425daadc31b910cf1988532b7379` |
| `programacion.fn_input_source_ref_eligibility_v1(p_run_id bigint)` | CONTROL [orientativa] | programacion.input_family_assessments | — | `f09fd261b752641a7637b237afe30e04` |
| `programacion.fn_input_stage_gate_summary(p_run_id bigint)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `00269d4620e587d75e352e01d5588c27` |
| `programacion.fn_input_stage_gate_summary_known_current_v1(p_run_id bigint, p_run_current boolean)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `67712c8c0128a9d400d5625d7e988eaa` |
| `programacion.fn_input_subject_depth_expected(p_pantalla_id integer, p_family_code text)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `411401b903f0d56b28e49976f1e5a2b5` |
| `programacion.fn_input_subject_depth_expected_v510(p_pantalla_id integer, p_family_code text)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `11084f2cba3d605769ebe5d9a12691cf` |
| `programacion.fn_input_subject_depth_expected_v510_rule_snapshot_candidate_v1(p_pantalla_id integer, p_family_code text)` | CONTROL [orientativa] | lf_ops.reglas | — | `70abaee8cb0426fc02b1e1d1c2cf088d` |
| `programacion.fn_input_successor_lineage_guard_m67_v1()` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `2030014dba045628f7d268e2a61a57eb` |
| `programacion.fn_input_v58_build_assertions(p_new_run_id bigint, p_parent_run_id bigint, p_family_code text)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `796accadd1b94940b70e8cb97af564c9` |
| `programacion.fn_input_validator_compaction_batch_v1(p_limit integer)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | programacion.input_family_assessments | `0a3c2491b6987b5fe1a770d9e6778b48` |
| `programacion.fn_input_validator_oracle_admission_v1(p_run_id bigint, p_family_code text)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `d03a3ef98489f06533dfe06f114a815d` |
| `programacion.fn_input_validator_semantic_scope_v1(p_run_id bigint)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `9241404e33abde5340a5e8c9129a36e6` |
| `programacion.fn_lf_profile_adapter_input_governance_resolve_v1(p_request_text text, p_adapters jsonb, p_consumer text)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `aa486273f5d3f734678e99cfed2dafb5` |
| `programacion.fn_t_remed_complete_v1(p_pantalla_id integer, p_consumer text)` | MIXTA [focal] | lf_ops.pantallas_politicas_reglas, lf_ops.reglas | lf_ops.pantallas_politicas_reglas | `a7eff4872fab6bebe0c57f448e38d46a` |
| `programacion.fn_t_remed_effective_rules_v1(p_pantalla_id integer, p_min_share numeric)` | DATO [orientativa] | lf_ops.reglas_pantallas | — | `ad5aecf15e12be5b55fdd1e8dac00295` |
| `programacion.fn_t_remed_global_rules_v1(p_min_share numeric)` | DATO [orientativa] | lf_ops.reglas, lf_ops.reglas_pantallas | — | `7d8b7a58f16bc5b53867c3322fd1befb` |
| `programacion.fn_t_remed_inherited_rules_v1(p_pantalla_id integer, p_min_share numeric, p_only_vigente boolean)` | DATO [orientativa] | lf_ops.reglas, lf_ops.reglas_pantallas | — | `e0fd4ce5fcd105b10858ebdc858fcc5d` |
| `programacion.fn_t_remed_layer1_selftest_v3()` | NO LECTURA DETECTADA; DML | — | lf_ops.reglas, lf_ops.reglas_pantallas | `c846328e71e805c999f29f44b4c5ed5a` |
| `programacion.fn_t_remed_open_decisions_v1(p_include_state_words boolean)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `7d3f28b65546062fef98ba67e59404d5` |
| `programacion.fn_t_remed_pending_deps_v1(p_regla_id bigint)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `d74876669be6b234e7a7af4c578fe17a` |
| `programacion.fn_t_remed_promote_v1(p_apply boolean, p_min_screens integer, p_limit integer)` | NO LECTURA DETECTADA; DML | — | lf_ops.reglas | `5b9d08393be4dab7e7a364bf506bd5ef` |
| `programacion.fn_t_remed_promote_v1(p_pantalla_id integer, p_consumer text)` | CONTROL [orientativa] | lf_ops.pantallas_politicas_reglas, lf_ops.reglas | — | `1a6216e39e10748ebba0e96535b4c11f` |
| `programacion.fn_t_remed_promote_v3(p_pantalla_id integer, p_consumer text)` | CONTROL [orientativa] | lf_ops.reglas, lf_ops.reglas_pantallas | lf_ops.reglas | `63fca3a053bd1b499dc10a44a493c04f` |
| `programacion.fn_t_remed_pt_make_v3(p_tag text, p_rules jsonb)` | NO LECTURA DETECTADA; DML | — | lf_ops.reglas, lf_ops.reglas_pantallas | `a1b64fb1117c5a30b6ddca0210ec5207` |
| `programacion.fn_t_remed_queue_v1(p_limit integer)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `1114e9501cd4ed515c92cb996793c3b5` |
| `programacion.fn_t_remed_raw_refs_v1(p_pantalla_id integer)` | DATO [orientativa] | lf_ops.reglas, lf_ops.reglas_pantallas | — | `603fa48779f296f63265fb75b3af1721` |
| `programacion.fn_t_remed_reconcile_v3(p_pantalla_id integer)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas, lf_ops.reglas_pantallas | — | `fdabe577e75b93100fd3b47e1fc6db71` |
| `programacion.fn_t_remed_revert_promotion_v1(p_change_id bigint)` | NO LECTURA DETECTADA; DML | — | lf_ops.reglas | `077a8c6fa6883e193a56d7407d463c54` |
| `programacion.fn_t_remed_rule_promotion_verdicts_v1(p_min_screens integer, p_regla_id bigint)` | CONTROL [orientativa] | lf_ops.reglas, lf_ops.reglas_pantallas | — | `92e8025b70d17e3de7da7206795ed73d` |
| `programacion.fn_t_remed_rule_promotion_verdicts_v2(p_regla_id bigint)` | CONTROL [orientativa] | lf_ops.reglas, lf_ops.reglas_pantallas | — | `b5a58e9de1eb09c8bb72f9a06f76c0cd` |
| `programacion.fn_t_remed_scope_judge_v1(p_min_share numeric)` | CONTROL [orientativa] | lf_ops.reglas, lf_ops.reglas_pantallas | — | `433445c108c36b25cf26f5a1bddb7a99` |
| `programacion.fn_t_remed_screen_status_v1(p_pantalla_id integer)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `1bd5ae72b6b113089d08014dbb0dc758` |
| `programacion.fn_t_remed_selftest_v1()` | CONTROL [orientativa] | lf_ops.reglas, lf_ops.reglas_pantallas | — | `f1d23289b2b5e8ddfb5ba678ff3805e3` |
| `public.fn_ig_m105_cp2_attest_run_v1(p_run_id bigint)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `8a00cd99c890fff5531921e7c8706c8b` |
| `public.fn_input_governance_validator_resume_context_core_v1(p_run_id bigint)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `41519df142b3fdc867134b86f9888a8f` |
| `public.lf_input_family_catalog_context_v1(p_pantalla_id integer)` | MIXTA [focal] | public.v_lf_input_family_coverage_by_screen_v1 | — | `0efbaa02411e52b0c4e0ab83c3ac20e8` |
| `public.lf_input_family_catalog_receipts_for_run_v1(p_execution_id text)` | CONTROL [orientativa] | public.v_lf_input_family_coverage_by_screen_v1 | — | `dad4d36ce764fa8d11dc65e603e3d049` |
| `public.lf_input_family_reuse_before_propose_v1(p_pantalla_id integer, p_family_code text, p_run_id bigint)` | MIXTA [focal] | public.v_lf_input_family_coverage_by_screen_v1 | — | `40e00836ffa99e2fa6ae98a7e2ac1d03` |
| `public.lf_input_family_reuse_claims_gate_v1(p_pantalla_id integer, p_claims jsonb)` | CONTROL [focal] | public.v_lf_input_family_coverage_by_screen_v1 | — | `f0e41d043a695f414a536b4aad5f13a8` |
| `public.lf_input_family_semantic_transfer_eval_v1(p_pantalla_id integer, p_claims jsonb, p_judge jsonb)` | CONTROL [orientativa] | programacion.input_family_inheritable_sources_v1 | — | `64ef35b87a053a0ae96d930ec78e1046` |
| `public.lf_input_gov_recuration_allowlist_v1()` | CONTROL [orientativa] | lf_ops.reglas | — | `dbebdfaf5869ee1aff98961da13cd029` |
| `public.lf_input_safe_autofix_independent_review_v1(p_run_id bigint)` | CONTROL [orientativa] | lf_ops.reglas, programacion.input_readiness_runs | — | `0315188dba52534721c18dc90af3d3f0` |
| `public.lf_profile_execution_channel_context_v1(p_execution_id text, p_base_context jsonb, p_handoff jsonb)` | DATO [focal] | lf_ops.reglas, lf_ops.reglas_pantallas | — | `9302760ee29525f02832c628eed397d7` |
| `public.lf_profile_ig_ticket_verify_v1(p_ticket uuid, p_pantalla_id integer, p_run_id bigint, p_consumer text)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `f003024ec80f7e30a162633db035a0e1` |
| `public.lf_profile_step50_rule_effect_after_v1(p_profile_execution_id text, p_train_execution_id text, p_rule_code text)` | REF TEXTUAL; no lectura demostrada | — | — | `75f3278336a89c412184f1305ac82ac9` |
| `public.lf_profile_step50_rule_effect_guard_v1(p_execution_id text, p_output jsonb)` | CONTROL [focal] | lf_ops.reglas, lf_ops.reglas_pantallas | — | `23128b6e12c302358a40b47830b38ae0` |
| `public.lf_profile_step50_rule_snapshot_v1(p_rule_code text)` | CONTROL [focal] | lf_ops.reglas | — | `7bd1e3d1b29d3839fe7bc6d5c599a985` |
| `public.lf_router_search_v1(p_request_text text, p_limit integer)` | DATO [orientativa] | lf_ops.reglas | — | `ab618ba17aaf183c4f6a92b50472d368` |
| `public.lf_router_worker_return_v1(p_return jsonb)` | REF TEXTUAL; no lectura demostrada | — | — | `ca0d89cdaa2c64b40102868655111525` |
| `public.lf_t_remed_independent_review_v1(p_pantalla_id integer)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.pantallas_politicas_reglas, lf_ops.reglas, lf_ops.reglas_pantallas | — | `a52acbf8cf3eb463948127b8fca0e63e` |
| `public.lf_t_remed_judge_v3(p_pantalla_id integer)` | CONTROL [orientativa] | lf_ops.reglas, lf_ops.reglas_pantallas | — | `af46ffd0f6182fe7090ab2c331b9f916` |
| `transversal.programming_agent_knowledge_privileged_v1(p_source text)` | CONTROL [focal] | transversal.prevention_rules | — | `c2c96d4bd7b5b41399e743bcd878500f` |

## 6. Inventario ampliado — fuera del foco nominal (no atribuir a perfiles)

| Firma SQL | Tipo / grado de evidencia | FROM/JOIN textual | DML textual | MD5 definición |
|---|---|---|---|---|
| `lf_ops.fn_b2b_native_numeric_id(p_entity_type text, p_alias text)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `33ea9896ae30be674a8af890953baa69` |
| `lf_ops.lf_legado_alcance_v1(p_regla integer)` | MIXTA/POR CONFIRMAR [orientativa] | reglas, reglas_pantallas | — | `1beb78d009bc98ab9c8866ddc114a603` |
| `lf_ops.lf_legado_sombra_regla_v1(p_regla integer, p_corrida timestamp with time zone)` | MIXTA/POR CONFIRMAR [orientativa] | reglas | — | `41548700985e831104f04ecc8bc13192` |
| `lf_ops.lf_legado_sombra_v1(p_guardar boolean)` | MIXTA/POR CONFIRMAR [orientativa] | reglas | — | `1120cd4bd158ee9fac338bb84e6c059d` |
| `lf_ops.lf_puente2_autotest_v1()` | CONTROL [orientativa] | reglas, reglas_pantallas | reglas, reglas_pantallas | `305c89ecf967f1443e96f30ee8f77ef3` |
| `lf_ops.lf_puente_autotest_v1()` | CONTROL [orientativa] | v_reglas_compat_v1 | — | `78f22a85306bfebfe678d0452c7ee55d` |
| `lf_ops.nucleo_regla_evaluar_v1(p_regla text, p_registrar boolean)` | REF TEXTUAL; no lectura demostrada | — | — | `7fa30f8cc3a66b895916aa8b0dcafc0f` |
| `lf_ops.nucleo_regla_proponer_v1(p jsonb, p_aplicar boolean)` | REF TEXTUAL; no lectura demostrada | — | — | `473e02146d1d3a43a7f3b81e58a20c1d` |
| `overall_design.fn_onboarding_screen_tree_detail(p_screen_id text)` | REF TEXTUAL; no lectura demostrada | — | — | `3c89c3dc4dff32b6ec255be4f9522e05` |
| `private.fn_lf_ig_human_decision_live_disposition_v1(p_proposal_id bigint)` | CONTROL [orientativa] | programacion.input_readiness_runs | — | `d79b4ff3dfe1c2da5c2fdf8929d1ea9c` |
| `private.fn_lf_ig_human_decision_source_currentness_v1(p_proposal_id bigint)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `b6e66738a795b7b628e619ba472817a9` |
| `private.fn_r5e_vacuum_finalize_v1()` | REF TEXTUAL; no lectura demostrada | — | — | `e4d2ddaef6b90ece853940d1f0bb9bb6` |
| `programacion.fn_engineering_historical_evidence_reevaluate_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_apply boolean)` | CONTROL [orientativa] | programacion.input_family_assessments, programacion.input_readiness_runs | — | `60403707728057d3591b457034ecd052` |
| `programacion.fn_engineering_structured_source_ref_resolve_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_apply boolean)` | CONTROL [orientativa] | programacion.input_family_assessments | — | `6015c12528136a257ebd8b044858f7b1` |
| `programacion.fn_lf_family_ref_member_guard_v1()` | CONTROL [orientativa] | programacion.input_family_inheritable_sources_v1 | — | `f3b6b5faf31acd45e050fce21ebc005f` |
| `programacion.fn_lf_family_ref_source_guard_v1()` | CONTROL [orientativa] | lf_ops.reglas | — | `ceeccccd17bce46ec1c90291327eef56` |
| `programacion.fn_source_rule_authority(p_rule_codes text[])` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `4c5a29d216d491fb13c2495d17601d81` |
| `public.lf_asset_snapshot_sha_v1(p_asset_type text, p_code text)` | CONTROL [orientativa] | lf_ops.reglas, lf_ops.reglas_pantallas | — | `b5f279f4c090faa1b4e7bb2d3ea0f35a` |
| `public.lf_external_baseline_sync_policy_v1()` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `9d008941450b2e130e83d2355240b7d6` |
| `public.lf_ig_rule_cycle_once_v3(p_parent text, p_rule text, p_source_sha256 text, p_decision jsonb, p_report_evidence_ref text)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `1c5ba0c02d2a24f6a0fd7bdfbacd5f6b` |
| `public.lf_ig_rule_finalize_v2(p_child text)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | lf_ops.reglas | `df1acd69a46b8bc4a6c257d95cc9a47a` |
| `public.lf_ig_rule_owner_decide_v2(p_parent text, p_rule text, p_source_sha256 text, p_decision jsonb)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas, lf_ops.reglas_pantallas | — | `98372407a52b87a464da597d24a408cb` |
| `public.lf_ig_step70_functional_train_auto_v1(p_parent text)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas, lf_ops.reglas_pantallas | — | `03ed54da90b74502f836e81ffebd1fe6` |
| `public.lf_nucleo_autotest_conjunto_v1()` | REF TEXTUAL; no lectura demostrada | — | — | `82ca38ad79c2ff8c8f9666fc81fea467` |
| `public.lf_regla_candidate_write_v1(p_execution_id text, p_action_code text, p_codigo text, p_categoria text, p_titulo text, p_descripcion text, p_razon text, p_valor_config jsonb, p_es_transversal boolean, p_origen text)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | lf_ops.reglas | `df7f5ea829bdb1eea71272d00dec08b9` |
| `public.lf_regla_create_preflight_v1(p_request_text text)` | CONTROL [orientativa] | lf_ops.reglas | — | `f37276eda915b54ef492313146c58870` |
| `public.lf_regla_pantalla_link_v1(p_execution_id text, p_regla_codigo text, p_pantalla_id integer, p_nota text)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas, lf_ops.reglas_pantallas | lf_ops.reglas_pantallas | `915f9be58ad48c8a839316b7a65fb561` |
| `public.lf_rule_exploration_materialize_candidate_v1(p_exploration_id uuid, p_completed_payload jsonb, p_consumer text, p_actor_execution_id text)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `55cb32936d0360ed8580bde82b1bd6dc` |
| `public.lf_rule_exploration_prepare_v1(p_exploration_id uuid, p_consumer text)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `4e6e54367c1e5650051063a783574877` |
| `public.lf_rule_promotion_apply_v1(p_promotion_id text)` | NO LECTURA DETECTADA; DML | — | lf_ops.reglas | `d7fe763c999db6f6259b6b1e2bd69644` |
| `public.lf_rule_promotion_auto_apply_v1(p_execution_id text, p_rule_code text)` | CONTROL [orientativa] | lf_ops.reglas | — | `43132bfa0977b32b5a03a8528474605e` |
| `public.lf_rule_promotion_report_v1(p_page integer, p_size integer)` | CONTROL [orientativa] | lf_ops.reglas, lf_ops.reglas_pantallas | — | `e3e521aaa933604de88d697196f54564` |
| `public.lf_rule_promotion_request_v1(p_execution_id text, p_rule_code text, p_reason text)` | CONTROL [orientativa] | lf_ops.reglas | — | `c9ea842b868343a1ce8a42e16b07deed` |
| `public.lf_rule_promotion_score_v1(p_execution_id text, p_rule_code text)` | CONTROL [orientativa] | lf_ops.reglas | — | `4d63984e10f0c8d97cf3a393353fda91` |
| `public.lf_skill_h_rule_create_propose_v1(p_input jsonb)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `e2cf37423e91f7d2921e9470605ca474` |
| `public.lf_skill_h_rule_link_propose_v1(p_input jsonb)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `025b6f7355577b4095f8cc6e5b45dba4` |
| `public.lf_skill_h_rule_update_propose_v1(p_input jsonb)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `c9696418d7404df55b3af28082abaa4f` |
| `public.lf_skill_h_screen_rules_snapshot_v1(p_input jsonb)` | CONTROL [orientativa] | lf_ops.reglas, lf_ops.reglas_pantallas | — | `57f61c07f79504ffa9bfab4f9621718e` |
| `public.lf_skill_o_rule_create_v2(p_child text, p_input jsonb, p_parent text, p_run text, p_request_sha text)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `2e436b801e8f3136934ccae538d2d9c9` |
| `public.lf_skill_o_rule_update_v1(p_child text, p_input jsonb, p_parent text, p_run text, p_request_sha text)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas, lf_ops.reglas_pantallas | — | `dc97a0e7c65b65ae1951e2da86c6238b` |
| `public.lf_skill_o_rule_update_v2(p_child text, p_input jsonb, p_parent text, p_run text, p_request_sha text)` | MIXTA/POR CONFIRMAR [orientativa] | lf_ops.reglas | — | `5d0becef9b514ce03a2977e1fe442b00` |
| `public.lf_skill_rule_child_readback_v1(p_parent text, p_run text, p_child text)` | CONTROL [orientativa] | lf_ops.reglas | — | `85b22ffafeeb740d1c3ba403ac21190e` |
| `saly.nucleo_regla_evaluar_v1(p_regla text, p_registrar boolean)` | REF TEXTUAL; no lectura demostrada | — | — | `e92725cb677057acaed7659e4efa7d41` |
| `saly.nucleo_regla_proponer_v1(p jsonb, p_aplicar boolean)` | REF TEXTUAL; no lectura demostrada | — | — | `442f3c0a7a21deb50f3e42cac9eac2c3` |

## 7. Consultas reproducibles y prueba real

Inventario SQL (repetir en transacción READ ONLY, conservar firmas y hash; no invoca funciones):
```sql
BEGIN READ ONLY;
WITH f AS (SELECT n.nspname sch,p.proname fn,pg_get_function_identity_arguments(p.oid) args,lower(p.prosrc) src,md5(pg_get_functiondef(p.oid)) hash FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.prokind='f' AND n.nspname NOT IN ('pg_catalog','information_schema') AND n.nspname NOT LIKE 'pg_%'), x AS (SELECT *,array(SELECT DISTINCT m[1] FROM regexp_matches(src,'\m(?:from|join)\s+(?:only\s+)?((?:lf_ops\.)?reglas|(?:lf_ops\.)?reglas_pantallas|(?:lf_ops\.)?pantallas_politicas_reglas|(?:public\.)?lf_prevention_rules|(?:transversal\.)?prevention_rules|(?:programacion\.)?input_family_(?:assessments|inheritable_members_v1|inheritable_sources_v1|reuse_map_v1)|(?:public\.)?v_lf_input_family_coverage_by_screen_v1|(?:lf_ops\.)?v_reglas_compat_v1|(?:programacion\.)?input_readiness_runs)\M','g') m ORDER BY 1) reads,array(SELECT DISTINCT m[1] FROM regexp_matches(src,'\m(?:update|insert\s+into|delete\s+from|truncate(?:\s+table)?)\s+(?:only\s+)?((?:lf_ops\.)?reglas|(?:lf_ops\.)?reglas_pantallas|(?:lf_ops\.)?pantallas_politicas_reglas|(?:public\.)?lf_prevention_rules|(?:transversal\.)?prevention_rules|(?:programacion\.)?input_family_(?:assessments|inheritable_members_v1|inheritable_sources_v1|reuse_map_v1)|(?:public\.)?v_lf_input_family_coverage_by_screen_v1|(?:lf_ops\.)?v_reglas_compat_v1|(?:programacion\.)?input_readiness_runs)\M','g') m ORDER BY 1) writes FROM f WHERE src ~ '\m((?:lf_ops\.)?reglas|(?:lf_ops\.)?reglas_pantallas|(?:lf_ops\.)?pantallas_politicas_reglas|(?:public\.)?lf_prevention_rules|(?:transversal\.)?prevention_rules|(?:programacion\.)?input_family_(?:assessments|inheritable_members_v1|inheritable_sources_v1|reuse_map_v1)|(?:public\.)?v_lf_input_family_coverage_by_screen_v1|(?:lf_ops\.)?v_reglas_compat_v1|(?:programacion\.)?input_readiness_runs)\M') SELECT sch,fn,args,hash,reads,writes FROM x ORDER BY 1,2,3;
ROLLBACK;
```
Dependencias estructurales de vistas:
```sql
BEGIN READ ONLY;
WITH targets AS (SELECT c.oid,n.nspname||'.'||c.relname AS ref FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname||'.'||c.relname IN ('lf_ops.reglas','lf_ops.reglas_pantallas','lf_ops.pantallas_politicas_reglas','lf_ops.v_reglas_compat_v1','transversal.prevention_rules','public.lf_prevention_rules','programacion.input_family_assessments','programacion.input_family_inheritable_members_v1','programacion.input_family_inheritable_sources_v1','programacion.input_family_reuse_map_v1','public.v_lf_input_family_coverage_by_screen_v1','programacion.input_readiness_runs')) SELECT n.nspname sch,c.relname name,md5(pg_get_viewdef(c.oid,true)) hash,array_agg(DISTINCT t.ref ORDER BY t.ref) refs FROM pg_rewrite w JOIN pg_class c ON c.oid=w.ev_class JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_depend d ON d.classid='pg_rewrite'::regclass AND d.objid=w.oid AND d.refclassid='pg_class'::regclass JOIN targets t ON t.oid=d.refobjid AND t.oid<>c.oid WHERE c.relkind IN ('v','m') GROUP BY 1,2,c.oid ORDER BY 1,2;
ROLLBACK;
```
Prueba PG17 real (candidatos textuales, no E2E ni prueba funcional del runtime). **22/22 PASS**, pg_version=17.6, read_only=on, sin fallos. Fixture positiva/negativa, presencia/ausencia directa en cuerpos reales y dependencia estructural. Las muestras textuales no certifican ausencia en SQL dinámico o indirecto.
```sql
BEGIN READ ONLY;
WITH fixtures(label,src,expected) AS (VALUES
('data','select * from lf_ops.reglas',true),('control','select * from transversal.prevention_rules',true),('coverage','select * from programacion.input_family_assessments',true),('join','select * from x join lf_ops.reglas_pantallas r on true',true),('compat','select * from lf_ops.v_reglas_compat_v1',true),('write_only','update lf_ops.reglas set titulo = titulo',false),('ref_only','x := ''lf_ops.reglas'';',false),('prefix_collision','select * from lf_ops.reglas_versiones',false),('suffix_collision','select * from lf_ops.reglas_pantallas_shadow',false),('unrelated','select * from lf_ops.pantallas',false)
), expected_live(signature,rel,expected) AS (VALUES
('public.lf_profile_execution_channel_context_v1(text,jsonb,jsonb)','lf_ops.reglas',true),
('programacion.fn_input_effective_rule_links_v1(integer,text)','lf_ops.reglas',true),
('programacion.fn_input_governance_ekb_checkpoint(text,integer,bigint)','public.lf_prevention_rules',true),
('programacion.fn_input_resolve_source_ref_v510(jsonb,integer,bigint)','transversal.prevention_rules',true),
('public.lf_profile_step50_rule_snapshot_v1(text)','lf_ops.reglas',true),
('public.lf_input_family_reuse_before_propose_v1(integer,text,bigint)','public.v_lf_input_family_coverage_by_screen_v1',true),
('public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)','lf_ops.reglas',false),
('programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text)','lf_ops.reglas',false),
('programacion.fn_input_governance_ekb_checkpoint(text,integer,bigint)','lf_ops.reglas',false)
), checks AS (
 SELECT 'fixture_'||label AS name, (src ~ '\m(?:from|join)\s+(?:only\s+)?((?:lf_ops\.)?reglas|(?:lf_ops\.)?reglas_pantallas|(?:lf_ops\.)?pantallas_politicas_reglas|(?:public\.)?lf_prevention_rules|(?:transversal\.)?prevention_rules|(?:programacion\.)?input_family_(?:assessments|inheritable_members_v1|inheritable_sources_v1|reuse_map_v1)|(?:public\.)?v_lf_input_family_coverage_by_screen_v1|(?:lf_ops\.)?v_reglas_compat_v1|(?:programacion\.)?input_readiness_runs)\M') IS NOT DISTINCT FROM expected AS pass FROM fixtures
 UNION ALL SELECT 'live_'||signature||':'||rel, CASE WHEN p.oid IS NULL THEN false ELSE (EXISTS(SELECT 1 FROM regexp_matches(lower(p.prosrc),'\m(?:from|join)\s+(?:only\s+)?((?:lf_ops\.)?reglas|(?:lf_ops\.)?reglas_pantallas|(?:lf_ops\.)?pantallas_politicas_reglas|(?:public\.)?lf_prevention_rules|(?:transversal\.)?prevention_rules|(?:programacion\.)?input_family_(?:assessments|inheritable_members_v1|inheritable_sources_v1|reuse_map_v1)|(?:public\.)?v_lf_input_family_coverage_by_screen_v1|(?:lf_ops\.)?v_reglas_compat_v1|(?:programacion\.)?input_readiness_runs)\M','g') m WHERE m[1]=e.rel)) IS NOT DISTINCT FROM e.expected END FROM expected_live e LEFT JOIN pg_proc p ON p.oid=to_regprocedure(e.signature)
 UNION ALL SELECT 'view_prevention_dependency',exists(SELECT 1 FROM pg_rewrite w JOIN pg_depend d ON d.classid='pg_rewrite'::regclass AND d.objid=w.oid WHERE w.ev_class='public.lf_prevention_rules'::regclass AND d.refclassid='pg_class'::regclass AND d.refobjid='transversal.prevention_rules'::regclass)
 UNION ALL SELECT 'view_coverage_dependency',exists(SELECT 1 FROM pg_rewrite w JOIN pg_depend d ON d.classid='pg_rewrite'::regclass AND d.objid=w.oid WHERE w.ev_class='public.v_lf_input_family_coverage_by_screen_v1'::regclass AND d.refclassid='pg_class'::regclass AND d.refobjid='lf_ops.reglas'::regclass)
 UNION ALL SELECT 'distinct_prevention_vs_business', 'transversal.prevention_rules'::regclass <> 'lf_ops.reglas'::regclass
)
SELECT current_setting('server_version') pg_version,current_setting('transaction_read_only') read_only,count(*) tests,count(*) FILTER(WHERE pass) passed,coalesce(jsonb_agg(name ORDER BY name) FILTER(WHERE NOT pass),'[]'::jsonb) failed FROM checks;
ROLLBACK;
```
Conteos de invariantes:
```sql
SELECT (SELECT count(*) FROM lf_ops.reglas) AS lf,(SELECT count(*) FROM saly.reglas) AS saly,(SELECT count(*) FROM lf_ops.nucleo_reglas) AS core_lf,(SELECT count(*) FROM saly.nucleo_reglas) AS core_saly,(SELECT count(*) FROM transversal.prevention_rules) AS prevention,(SELECT count(*) FROM programacion.input_family_inheritable_sources_v1) AS sources,(SELECT count(*) FROM programacion.input_family_inheritable_members_v1) AS members,(SELECT count(*) FROM programacion.input_family_reuse_map_v1) AS reuse;
```
Consultas complementarias: obtener `pg_get_functiondef(to_regprocedure('firma completa'))` para clasificación detallada; `pg_get_viewdef('public.v_lf_input_family_coverage_by_screen_v1'::regclass,true)`; consultar catálogos EKB por códigos y no invocar ningún escritor. Para dependencias de funciones, revisar llamadas calificadas y firma, no asumir que coincidencia de nombre resuelve sobrecarga.

## 8. EKB, plan y condición de cierre

EKB focal leída antes del análisis: LF-NUCLEO-A4-DIRECT-LEGACY-READER-CI-20261121-001 RESUELTO (guard solo cambios nuevos; no garantiza todo SQL dinámico); LF-NUCLEO-LEGACY-RULES-NOT-EVALUABLE-20261121-001 y LF-NUCLEO-IG-FAMILIES-WITHOUT-RULES-20261120-001 ACTIVO (no se modifica estado); LF-IG-SKILL-FAILED-STEP40-FINDING-20261114-001 ACTIVO (conservar hallazgo y prohibición efecto); LF-PROFILE-STEP80-IG-CLEARANCE-OMITTED-20261116-001 CANDIDATO (conservar fail-closed); LF-NUCLEO-MIGRATION-CANDIDATE-LEGACY-COEXISTENCE-20261121-001 RESUELTO; PROFILE-CREATOR-EKB-PREFLIGHT-MERGE-ORDER-005 ACTIVO (preflight real documentado). No se detectó incidente reproducido que exija nuevo EKB; diagnóstico de referencias existentes no es corrección ni motivo para duplicar registros.
Tablero original 70/100 sin cambios. DP-IG-01 cerrado. DP-IG-02 inventario listo, pendiente únicamente de PR/PASE/Train/readback; al cumplir, subplan 2/5 (40%), sin añadir puntos al denominador 100. DP-IG-03..05 no iniciados en este ciclo; definición exacta de plan original sigue pendiente de recuperación; D8 pendiente de dueño, no se anticipa. No atribuir éxito runtime ni migración, no marcar A4 ejecutado completo, ni publicar reglas. Siguiente ciclo no iniciado.
