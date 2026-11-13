-- L35 / 43 C — SELECT ONLY / negative screening, NOT a certificate of zero external effects.
-- Each ID comes verbatim from L34 SELECT readback of frozen L33 235 cohort.
-- SQL must return EXACTLY 43 rows. This proves only listed DB-local paths.
WITH cohort(id) AS MATERIALIZED (SELECT unnest(ARRAY[
'09b90743-6f2c-4651-a6b9-739bd41d35e7',
'49cc7bcd-cb04-443f-a7ec-04f289d3dc10',
'5c8f0238-b53a-4560-a5bb-5a7f8bffd3e6',
'EXEC-ACTUALIZACION-SKILL-PROFILE-CREATOR-S22-PL005-20260916-002',
'EXEC-ADAPTER-FACTORY-CORE-REUSE-20260831-001',
'EXEC-ASSURANCE-REDESIGN-EKB-CI-20260926-001',
'EXEC-BOOTSTRAP-ACTUALIZACION-APP-SHELL-LF-20260915-001',
'EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001',
'EXEC-BOOTSTRAP-CREACION-APP-SHELL-LF-20260915-001',
'EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001',
'EXEC-BOOTSTRAP-EDGE-FUNCTION-OP-20261014-001',
'EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-LF-20260913-001',
'EXEC-BOOTSTRAP-PASE-F07-X03-20261007-001',
'EXEC-BOOTSTRAP-PROMOCION-REGLA-LF-R43378647210',
'EXEC-CARD-UPDATE-I8-EXPERTISE-GATE-20260914-001',
'EXEC-CARD-UPDATE-I8-NEG-PROD-ACTIVATION-20260915-001',
'EXEC-CARD-UPDATE-I8-NEG-ROUTER-ACTIVATION-20260915-001',
'EXEC-CARD-UPDATE-I8-NEG-STALE-QUAL-20260915-001',
'EXEC-CHECKPOINT-OP-BOOTSTRAP-20261014-001',
'EXEC-IG-M6-2-LEDGER-20261007-CGPT-V1',
'EXEC-IG-M6-2-ORCH-20261007-CGPT-V1',
'EXEC-IG-M7-6-INDEP-20261004-001',
'EXEC-IG-M7-6-LEDGER-20261004-001',
'EXEC-IG-M7-6-ORCH-20261004-001',
'EXEC-PACK-VALIDATION-REBIND-PR1128-20260927-001',
'EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001',
'EXEC-ROUTER-CONTRACT-GATE2-20261028',
'EXEC-ROUTER-MIGRATION-SOURCE-PARITY-20260828-001',
'EXEC-RUNTIME-UPDATE-REENABLE-20260919-001',
'EXEC-S28-CI-MAIN-CURRENTNESS-SELF-UPDATE-20260918-001',
'EXEC-S30-CI-APPLICABILITY-REPAIR-20260918-001',
'EXEC-S30-DIAGNOSTIC-SEARCH-BUDGET-EKB-20260916-001',
'EXEC-S30-LF-ASSURANCE-METHOD-V1-GATED-20260916-001',
'EXEC-S30-LF-ASSURANCE-METHOD-V1-GATED-20260916-002',
'EXEC-S35-DDI-STRATEGY-CREATION-20260913-001',
'GOV-ACTUALIZACION-ADAPTER-MATERIALIZATION-20260829-001',
'IG_M97_LEDGER_BUNDLE_187_1068_20261009',
'IG_M97_ORCH_BUNDLE_187_1068_20261009',
'IG_M97_PRODUCER_BUNDLE_187_1068_20261009',
'LF-ACT0058-20260901-1848-AUTOLEARN',
'LF-AUTOLEARN-CAPTURE-REEVALUA-20260901-001',
'LF-AUTOLEARN-HOMOLOG-REEVALUA-20260901-001',
'LF-AUTOLEARN-RUN-20260901-037'
]::text[])),
screen AS (
 SELECT c.id, r.operation_code,r.status,r.lease_expires_at,
 (SELECT count(*) FROM public.lf_operation_effect_guard e WHERE e.execution_id=c.id) AS effect_guards,
 (SELECT count(*) FROM public.lf_operation_execution_steps s WHERE s.execution_id=c.id
   AND s.status IN ('PASS_CLEAN','STEP_PASS_WITH_EVIDENCE')) AS positive_steps,
 (SELECT count(*) FROM public.lf_skill_invocation_v1 i
   WHERE i.parent_execution_id=c.id OR i.child_execution_id=c.id) AS skill_invocations,
 (SELECT count(*) FROM public.lf_operation_execution ch
   WHERE ch.created_by_execution_id=c.id AND ch.execution_id<>c.id) AS child_runs,
 (SELECT count(*) FROM public.lf_operation_gate_check_results g
   WHERE g.execution_id=c.id OR g.run_id=c.id) AS gate_results,
 (SELECT count(*) FROM public.lf_ig_rule_change_v2 g
   WHERE g.parent_execution_id=c.id OR g.child_execution_id=c.id) AS rule_changes,
 (SELECT count(*) FROM public.lf_ig_owner_decision_v2 d
   WHERE d.parent_execution_id=c.id) AS owner_decisions,
 (SELECT count(*) FROM public.lf_router_scope_receipt_v1 s
   WHERE s.execution_id=c.id) AS router_receipts,
 (SELECT count(*) FROM public.lf_ig_native_chat_receipt_v1 n
   WHERE n.execution_id=c.id) AS native_receipts,
 (SELECT count(*) FROM public.lf_activos x
   WHERE x.created_by_execution_id=c.id OR x.updated_by_execution_id=c.id) AS asset_writes,
 (SELECT count(*) FROM public.lf_activo_relaciones x
   WHERE x.created_by_execution_id=c.id OR x.updated_by_execution_id=c.id) AS asset_relation_writes,
 (SELECT count(*) FROM public.lf_cards x
   WHERE x.created_by_execution_id=c.id OR x.updated_by_execution_id=c.id) AS card_writes
 FROM cohort c JOIN public.lf_operation_execution r ON r.execution_id=c.id
)
SELECT *, (effect_guards+positive_steps+skill_invocations+child_runs+gate_results+rule_changes+
 owner_decisions+router_receipts+native_receipts+asset_writes+asset_relation_writes+card_writes) AS local_positive_links,
 CASE WHEN (effect_guards+positive_steps+skill_invocations+child_runs+gate_results+rule_changes+
 owner_decisions+router_receipts+native_receipts+asset_writes+asset_relation_writes+card_writes)=0
 THEN 'NO_LINK_IN_12_CHECKED_PATHS_NOT_NO_EFFECT' ELSE 'POSITIVE_LOCAL_LINK_INVESTIGATE' END AS screening,
 false AS external_sinks_exhaustively_verified,
 false AS safe_to_retry,
 false AS no_effect_certified,
 transaction_timestamp() AS observed_at_utc
FROM screen ORDER BY id COLLATE "C";