#!/usr/bin/env python3
from __future__ import annotations
import json,re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent
SHA40=re.compile(r"^[0-9a-f]{40}$")
class ContractError(ValueError): pass
def load(n): return json.loads((ROOT/n).read_text(encoding="utf-8"))

def validate_request_context(o):
    req={"schema_version","request_identity","objective","target_hints","source_refs","provided_facts","constraints","ambiguities","no_solution_inferred"}
    if set(o)!=req: raise ContractError("REQUEST_CONTEXT_KEYS_MISMATCH")
    if o["schema_version"]!="REQUEST_CONTEXT_V1": raise ContractError("REQUEST_CONTEXT_VERSION")
    if o["no_solution_inferred"] is not True: raise ContractError("REQUEST_CONTEXT_SOLUTION_INFERENCE")
    if set(o["request_identity"])!={"request_ref","request_kind"}: raise ContractError("REQUEST_IDENTITY_KEYS")
    if len(o["request_identity"]["request_ref"].strip())<3: raise ContractError("REQUEST_REF")
    if o["request_identity"]["request_kind"] not in {"USER_REQUEST","SYSTEM_REQUEST","ISSUE","HANDOFF","FILE","EVENT","OTHER"}: raise ContractError("REQUEST_KIND")
    if set(o["objective"])!={"problem_statement","desired_outcome"}: raise ContractError("OBJECTIVE_KEYS")
    if not all(isinstance(o["objective"][k],str) and o["objective"][k].strip() for k in o["objective"]): raise ContractError("OBJECTIVE_EMPTY")
    if not isinstance(o["ambiguities"],list): raise ContractError("AMBIGUITIES_TYPE")
    for a in o["ambiguities"]:
        if set(a)!={"code","statement","materiality","resolution_state"}: raise ContractError("AMBIGUITY_KEYS")
        if a["materiality"] not in {"MATERIAL","NON_MATERIAL","UNKNOWN"}: raise ContractError("AMBIGUITY_MATERIALITY")
        if a["resolution_state"] not in {"OPEN","RESOLVED_FROM_SOURCE"}: raise ContractError("AMBIGUITY_STATE")

def validate_programming_entry(o):
    if o.get("schema_version")!="PROGRAMMING_ENTRY_CONTRACT_V1": raise ContractError("PROGRAMMING_ENTRY_VERSION")
    if o.get("canonical_upstream")!="ANALYSIS_IMPLEMENTATION_PACKAGE_V1": raise ContractError("PROGRAMMING_UPSTREAM")
    expected={"analysis_package_digest_required":True,"source_currentness_required":True,"exact_target_identity_required":True,"target_granularity_required":True,"authority_state_required":True,"implementation_state_required":True,"implementation_existing_delta_required":True,"implementation_existing_greenfield_redefinition_forbidden":True,"implementation_new_requires_no_current_implementation_evidence":True,"reuse_before_build_evidence_required":True,"applicable_design_bindings_required":True,"programming_context_snapshot_required":True,"programming_context_snapshot_receipt_required":True,"decision_context_required":True,"material_front_coverage_required":True,"analysis_stop_rule_required":True,"implementability_schema_required":True,"handoff_parity_receipt_required":True,"snapshot_currentness_decision_required":True,"scope_readiness_required":True,"only_ready_scopes_admissible":True,"partial_ready_requires_scope_isolation":True,"cross_scope_blocker_contamination_forbidden":True,"lossless_projection_required":True,"story_identity_required":False,"functional_version_required":False,"agent_task_required_at_upstream_admission":False}
    admission=o.get("admission",{})
    if set(admission.get("allowed_analysis_verdicts",[]))!={"READY","PARTIAL_READY"}: raise ContractError("PROGRAMMING_ADMISSION_VERDICTS")
    for k,v in expected.items():
        if admission.get(k)!=v: raise ContractError("PROGRAMMING_ADMISSION_"+k)
    tb=o.get("target_binding",{})
    if tb.get("state_dimensions_independent") is not True or tb.get("authority_state_does_not_imply_implementation_state") is not True: raise ContractError("PROGRAMMING_STATE_DIMENSIONS")
    if tb.get("authority_existing_implementation_new_allowed") is not True: raise ContractError("PROGRAMMING_PREDECLARED_NEW_IMPLEMENTATION")
    if tb.get("implementation_existing_requires_exact_revision_binding") is not True: raise ContractError("PROGRAMMING_EXISTING_IMPLEMENTATION_REVISION")
    if tb.get("implementation_new_requires_negative_current_implementation_evidence") is not True or tb.get("implementation_new_requires_reuse_assessment") is not True: raise ContractError("PROGRAMMING_NEW_IMPLEMENTATION_PROOF")
    if tb.get("design_binding_policy")!="CANONICAL_REF_PLUS_CURRENT_RESOLVED_VALUE" or tb.get("design_literal_is_not_authority") is not True: raise ContractError("PROGRAMMING_DESIGN_BINDING")
    if tb.get("implementation_strategy_owned_by")!="PG-03": raise ContractError("PROGRAMMING_STRATEGY_OWNER")
    s=o.get("programming_context_snapshot",{})
    if s.get("schema_version")!="PROGRAMMING_CONTEXT_SNAPSHOT_V1" or s.get("assembled_by")!="A9" or s.get("material_bindings_prepared_by")!="A6": raise ContractError("PROGRAMMING_CONTEXT_SNAPSHOT_IDENTITY")
    required_snapshot={"objective","target","target_granularity","authority_state","implementation_state","requirements[]","authority_bindings[]","applicable_rules[]","applicable_invariants[]","preserve[]","material_front_coverage","implementability_schema","decision_context","analysis_stop_rule","scope_front_matrix[]","scope_readiness[]","package_readiness","unresolved_material_items[]","source_refs[]","currentness_refs[]","snapshot_schema_digest_sha256","authority_fingerprint_sha256","source_snapshot_sha256"}
    if set(s.get("required_fields",[]))!=required_snapshot: raise ContractError("PROGRAMMING_CONTEXT_SNAPSHOT_FIELDS")
    mfc=s.get("material_front_coverage",{})
    if mfc.get("schema_version")!="MATERIAL_FRONT_COVERAGE_V1" or mfc.get("producer_unit")!="A7": raise ContractError("PROGRAMMING_MATERIAL_FRONT_COVERAGE_IDENTITY")
    if mfc.get("contract_ref")!="analysis_material_front_coverage_contract_v1.json" or mfc.get("must_preserve_full_artifact") is not True: raise ContractError("PROGRAMMING_MATERIAL_FRONT_COVERAGE_PRESERVATION")
    if mfc.get("scope_readiness_is_separate_dimension") is not True or mfc.get("absence_never_means_not_applicable") is not True: raise ContractError("PROGRAMMING_MATERIAL_FRONT_COVERAGE_BOUNDARY")
    if mfc.get("implementation_absence_alone_must_not_block") is not True: raise ContractError("PROGRAMMING_IMPLEMENTATION_ABSENCE_FALSE_BLOCKER")
    impl=s.get("implementability_schema",{})
    if impl.get("schema_version")!="IMPLEMENTABILITY_SCHEMA_V1" or impl.get("producer_unit")!="A6": raise ContractError("PROGRAMMING_IMPLEMENTABILITY_IDENTITY")
    if impl.get("contract_ref")!="analysis_implementability_contract_v1.json" or impl.get("must_preserve_full_artifact") is not True: raise ContractError("PROGRAMMING_IMPLEMENTABILITY_PRESERVATION")
    if impl.get("technical_strategy_owned_by")!="PG-03" or impl.get("receiver_parity_policy_owned_by_next_boundary") is not True: raise ContractError("PROGRAMMING_IMPLEMENTABILITY_BOUNDARY")
    dc=s.get("decision_context",{})
    if dc.get("schema_version")!="ANALYSIS_DECISION_CONTEXT_V1" or dc.get("producer_unit")!="A5": raise ContractError("PROGRAMMING_DECISION_CONTEXT_IDENTITY")
    if dc.get("contract_ref")!="analysis_decision_context_adr_contract_v1.json" or dc.get("must_preserve_full_artifact") is not True: raise ContractError("PROGRAMMING_DECISION_CONTEXT_PRESERVATION")
    if dc.get("ready_scope_requires_no_unresolved_material_decision") is not True or dc.get("requires_owner_decision_propagates_to_scope_readiness") is not True or dc.get("blocked_adr_propagates_to_scope_readiness") is not True: raise ContractError("PROGRAMMING_DECISION_CONTEXT_READINESS")
    if dc.get("technical_strategy_owned_by")!="PG-03": raise ContractError("PROGRAMMING_DECISION_CONTEXT_STRATEGY_BOUNDARY")
    if dc.get("current_existing_decision_resolution_required") is not True or dc.get("pending_human_decision_packets_must_be_preserved") is not True: raise ContractError("PROGRAMMING_DECISION_CONTEXT_HUMAN_ROUTING")
    asr=s.get("analysis_stop_rule",{})
    if asr.get("schema_version")!="ANALYSIS_STOP_RULE_V1" or asr.get("producer_unit")!="A8": raise ContractError("PROGRAMMING_STOP_RULE_IDENTITY")
    if asr.get("contract_ref")!="analysis_stop_rule_contract_v1.json": raise ContractError("PROGRAMMING_STOP_RULE_CONTRACT")
    if asr.get("stop_requires_decision_stable") is not True or asr.get("stop_requires_all_material_fronts_accounted") is not True or asr.get("scope_readiness_policy_owned_separately") is not True: raise ContractError("PROGRAMMING_STOP_RULE_BOUNDARY")
    sr=s.get("scope_readiness_contract",{})
    if set(sr.get("status_values",[]))!={"READY","NEED_MORE_EVIDENCE","REQUIRES_DECISION","BLOCKED","NOT_APPLICABLE"}: raise ContractError("PROGRAMMING_SCOPE_READINESS_STATUS")
    required_scope={"scope_id","scope_kind","status","depends_on_scope_ids[]","material_front_refs[]","authority_refs[]","blockers[]","reason"}
    if set(sr.get("required_fields",[]))!=required_scope: raise ContractError("PROGRAMMING_SCOPE_READINESS_FIELDS")
    if sr.get("ready_requires_dependency_closure") is not True or sr.get("ready_requires_no_material_blocker") is not True or sr.get("blocked_scope_must_not_contaminate_ready_scope") is not True: raise ContractError("PROGRAMMING_SCOPE_READINESS_GUARDS")
    sfc=s.get("scope_front_consistency_contract",{})
    matrix_fields={"scope_id","front_id","front_status","front_closure","effect_on_scope","evidence_refs[]","reason"}
    if set(sfc.get("matrix_required_fields",[]))!=matrix_fields: raise ContractError("PROGRAMMING_SCOPE_FRONT_MATRIX_FIELDS")
    if set(sfc.get("effect_values",[]))!={"BLOCKS","PRESERVE","NOT_APPLICABLE"}: raise ContractError("PROGRAMMING_SCOPE_FRONT_EFFECT_VALUES")
    required_front_guards={"bidirectional_scope_front_mapping_required","required_blocked_front_blocks_every_bound_scope","ready_scope_forbids_blocking_front","reuse_as_is_closed_front_may_preserve_scope","not_applicable_front_must_not_block_scope","partial_ready_requires_every_ready_scope_front_clean","pg01_admission_requires_front_clean_ready_scope"}
    for k in required_front_guards:
        if sfc.get(k) is not True: raise ContractError("PROGRAMMING_SCOPE_FRONT_GUARD_"+k)
    pr=s.get("package_readiness_contract",{})
    if set(pr.get("values",[]))!={"READY","PARTIAL_READY","NEED_MORE_EVIDENCE","REQUIRES_DECISION","BLOCKED"}: raise ContractError("PROGRAMMING_PACKAGE_READINESS_VALUES")
    if pr.get("partial_ready_requires_at_least_one_ready_scope") is not True or pr.get("partial_ready_requires_independent_execution_boundary") is not True or pr.get("partial_ready_forbidden_when_cross_cutting_material_blocker_affects_ready_scope") is not True: raise ContractError("PROGRAMMING_PARTIAL_READY_GUARDS")
    ps=s.get("persistence",{})
    expected_persistence={
        "required":True,
        "capability":"DECISION_CONTEXT_ASOF",
        "capability_version_policy":"CURRENT",
        "record_entrypoint":"public.fn_lf_decision_context_asof_record_v1",
        "resolve_entrypoint":"public.fn_lf_decision_context_asof_resolve_v1",
        "store":"private.lf_decision_context_asof_v1",
        "mode":"APPEND_ONLY_ASOF_RECEIPT",
        "snapshot_extension_path":"extensions.programming_context_snapshot",
        "full_scope_payload_persisted":True,
        "scope_lookup_key":"scope_id",
        "pg01_must_resolve_exact_receipt_before_use":True,
        "resolved_context_digest_must_match_receipt":True,
        "memory_only_snapshot_forbidden":True,
        "latest_mutable_reinterpretation_forbidden":True,
        "authority_copy_forbidden":True,
        "canonical_refs_and_resolved_evidence_only":True,
        "new_snapshot_store_forbidden":True,
    }
    for k,v in expected_persistence.items():
        if ps.get(k)!=v: raise ContractError("PROGRAMMING_CONTEXT_PERSISTENCE_"+k)
    receipt_fields={"context_id","decision_ref","context_sha256","subject_ref","subject_version","decided_at","effective_at"}
    if set(ps.get("required_receipt_fields",[]))!=receipt_fields: raise ContractError("PROGRAMMING_CONTEXT_PERSISTENCE_RECEIPT_FIELDS")
    sc=s.get("snapshot_currentness_contract",{})
    if sc.get("authority_capability")!="CURRENTNESS_AUTHORITY" or sc.get("capability_version_policy")!="CURRENT": raise ContractError("PROGRAMMING_SNAPSHOT_CURRENTNESS_AUTHORITY")
    if set(sc.get("decision_values",[]))!={"CURRENT","CURRENT_REBOUND","STALE_AFFECTED","UNKNOWN_FAIL_CLOSED"}: raise ContractError("PROGRAMMING_SNAPSHOT_CURRENTNESS_VALUES")
    required_currentness_inputs={"context_sha256","snapshot_schema_digest_sha256","authority_fingerprint_sha256","source_snapshot_sha256"}
    if set(sc.get("required_inputs",[]))!=required_currentness_inputs: raise ContractError("PROGRAMMING_SNAPSHOT_CURRENTNESS_INPUTS")
    required_true={"same_fingerprint_reuse_required","same_current_snapshot_forbids_rediscovery","authority_fingerprint_change_requires_rebuild","snapshot_schema_digest_change_requires_rebuild","recorded_snapshot_immutable","mid_execution_rebind_forbidden","selective_affected_closure_required","dependency_completeness_required_for_auto_rebound","stale_affected_scope_blocks_affected_scope","unknown_state_fail_closed","worker_projection_invalidated_with_snapshot"}
    for k in required_true:
        if sc.get(k) is not True: raise ContractError("PROGRAMMING_SNAPSHOT_CURRENTNESS_"+k)
    if sc.get("global_main_sha_change_alone_causes_stale") is not False: raise ContractError("PROGRAMMING_SNAPSHOT_CURRENTNESS_MAIN_SHA")
    tp=s.get("transport_policy",{})
    if tp.get("small_material_stable")!="INLINE_RESOLVED_VALUE_PLUS_CANONICAL_REF" or tp.get("large_identified")!="EXACT_REF_ONLY" or tp.get("dynamic_or_staleness_sensitive")!="EXACT_REF_PLUS_TYPED_RESOLVER" or tp.get("irrelevant_to_current_batch")!="OMIT": raise ContractError("PROGRAMMING_CONTEXT_TRANSPORT")
    if s.get("rediscovery_without_trigger_forbidden") is not True: raise ContractError("PROGRAMMING_CONTEXT_REDISCOVERY")
    if set(s.get("allowed_requery_triggers",[]))!={"MISSING","STALE","CONTRADICTION","SOURCE_DRIFT","MATERIAL_NEW_QUESTION"}: raise ContractError("PROGRAMMING_CONTEXT_REQUERY_TRIGGERS")
    if s.get("typed_resolver_required_for_requery") is not True or s.get("freeform_source_query_when_typed_resolver_exists_forbidden") is not True: raise ContractError("PROGRAMMING_CONTEXT_TYPED_RESOLVER")
    if s.get("worker_projection_policy")!="MINIMUM_RELEVANT_SUBSET" or s.get("same_fingerprint_reuse_required") is not True or s.get("fingerprint_change_requires_rebuild") is not True: raise ContractError("PROGRAMMING_CONTEXT_REUSE")
    forbidden={"chosen_component_structure","chosen_framework_pattern","chosen_endpoint_design","chosen_internal_algorithm"}
    if set(s.get("technical_strategy_fields_forbidden",[]))!=forbidden: raise ContractError("PROGRAMMING_CONTEXT_STRATEGY_LEAK")
    hp=o.get("handoff_parity",{})
    if hp.get("schema_version")!="ANALYSIS_PROGRAMMING_HANDOFF_PARITY_CONTRACT_V1" or hp.get("contract_ref")!="analysis_programming_handoff_parity_contract_v1.json": raise ContractError("PROGRAMMING_HANDOFF_PARITY_IDENTITY")
    if hp.get("producer_unit")!="A9" or hp.get("consumer_unit")!="PG-01": raise ContractError("PROGRAMMING_HANDOFF_PARITY_BOUNDARY")
    if hp.get("shared_snapshot_schema_required") is not True or hp.get("exact_context_receipt_required") is not True or hp.get("lossy_material_projection_forbidden") is not True: raise ContractError("PROGRAMMING_HANDOFF_PARITY_GUARDS")
    c=o.get("compatibility",{})
    if c.get("action")!="EXTEND_ENTRY_BOUNDARY_DO_NOT_DUPLICATE_RUNTIME" or c.get("new_runtime_created") is not False: raise ContractError("PROGRAMMING_PARALLEL_RUNTIME")
    if c.get("story_direct_consumption_after_cutover") is not False: raise ContractError("PROGRAMMING_STORY_CUTOVER")
    db=o.get("downstream_control_bindings",{})
    expected_db={
        "canonical_analysis_package_contract":"analysis_implementation_package_contract_v1.json",
        "solution_partition_owner":"PG-04",
        "solution_partition_contract":"programming_solution_partition_contract_v1.json",
        "context_budget_owner":"PG-07",
        "context_budget_contract":"programming_context_budget_contract_v1.json",
        "programming_conflict_human_decision_owner":"PG-10",
        "programming_human_decision_contract":"programming_human_decision_routing_contract_v1.json",
        "pg01_does_not_claim_partition_or_context_budget_enforcement":True,
        "pg04_pg07_pg10_contracts_required_before_programming_v1_freeze":True,
    }
    for k,v in expected_db.items():
        if db.get(k)!=v: raise ContractError("PROGRAMMING_DOWNSTREAM_CONTROL_"+k)

def validate_analysis_decision_context(o):
    if o.get("schema_version")!="ANALYSIS_DECISION_CONTEXT_ADR_CONTRACT_V1" or o.get("unit")!="A5": raise ContractError("A5_IDENTITY")
    if set(o.get("input_contracts",[]))!={"REQUEST_CONTEXT_V1","ANALYSIS_CHANGE_CLASSIFICATION_V1","TARGETED_EVIDENCE_SET_V1","SHARED_CHANGE_IMPACT_ANALYSIS"}: raise ContractError("A5_INPUTS")
    if o.get("output_contract")!="DECISION_CONTEXT": raise ContractError("A5_OUTPUT")
    d=o.get("decision_context",{})
    if d.get("schema_version")!="ANALYSIS_DECISION_CONTEXT_V1": raise ContractError("A5_DECISION_CONTEXT_VERSION")
    if set(d.get("status_values",[]))!={"STABLE","UNRESOLVED","REQUIRES_DECISION","BLOCKED"}: raise ContractError("A5_STATUS_VALUES")
    required={"decision_id","subject_ref","scope_refs[]","material_question","status","options_considered[]","selected_option_ref","rationale","authority_refs[]","evidence_refs[]","currentness_refs[]","unresolved_questions[]","adr_disposition","adr_ref","persistence_ref","decision_fingerprint_sha256"}
    if set(d.get("required_fields",[]))!=required: raise ContractError("A5_REQUIRED_FIELDS")
    for k in ("material_question_must_be_evidence_derived","selected_option_requires_stable_status","unresolved_material_question_forbids_stable","technical_implementation_strategy_forbidden"):
        if d.get(k) is not True: raise ContractError("A5_DECISION_GUARD_"+k)
    a=o.get("adr_policy",{})
    if set(a.get("disposition_values",[]))!={"NOT_REQUIRED","REUSE_CURRENT_ADR","NEW_ADR_REQUIRED","ADR_BLOCKED"}: raise ContractError("A5_ADR_DISPOSITIONS")
    if not a.get("required_when_any") or not a.get("not_required_when_all"): raise ContractError("A5_ADR_TRIGGER_POLICY")
    e=a.get("existing_adr",{})
    if e.get("authority_surface")!="transversal.decision_log" or e.get("required_state")!="VIGENTE" or e.get("assert_entrypoint")!="programacion.fn_engineering_current_adr_assert_v1": raise ContractError("A5_ADR_CURRENT_AUTHORITY")
    if e.get("exact_adr_ref_required") is not True or e.get("stale_or_missing_adr_fails_closed") is not True: raise ContractError("A5_ADR_CURRENT_GUARDS")
    n=a.get("new_adr_required",{})
    if n.get("a5_may_not_self_approve_new_adr") is not True or n.get("status_must_be")!="REQUIRES_DECISION" or n.get("affected_scope_may_not_be_READY") is not True or n.get("local_provisional_override_forbidden") is not True: raise ContractError("A5_NEW_ADR_BOUNDARY")
    ps=o.get("persistence",{})
    expected={"capability":"DECISION_CONTEXT_ASOF","capability_version_policy":"CURRENT","record_entrypoint":"public.fn_lf_decision_context_asof_record_v1","resolve_entrypoint":"public.fn_lf_decision_context_asof_resolve_v1","mode":"APPEND_ONLY_ASOF_RECEIPT","new_store_forbidden":True,"historical_receipt_immutable":True,"currentness_authority":"CURRENTNESS_AUTHORITY","memory_only_decision_context_forbidden":True}
    for k,val in expected.items():
        if ps.get(k)!=val: raise ContractError("A5_PERSISTENCE_"+k)
    sr=o.get("scope_readiness_boundary",{})
    for k in ("ready_scope_requires_no_unresolved_material_decision","new_adr_required_propagates_requires_decision","blocked_adr_propagates_blocked","unrelated_independent_ready_scope_may_proceed"):
        if sr.get(k) is not True: raise ContractError("A5_SCOPE_"+k)
    ib=o.get("integration_boundary",{})
    if ib.get("a8_consumes_output_contract")!="DECISION_CONTEXT" or ib.get("a9_must_preserve_full_artifact") is not True or ib.get("programming_context_snapshot_field")!="decision_context" or ib.get("pg01_must_consume_losslessly") is not True or ib.get("pg03_retains_implementation_strategy_ownership") is not True: raise ContractError("A5_INTEGRATION")
    reuse=o.get("reuse",{})
    if set(reuse.get("reused_capabilities",[]))!={"DECISION_CONTEXT_ASOF","CURRENTNESS_AUTHORITY"} or reuse.get("reused_existing_authority_assertion")!="programacion.fn_engineering_current_adr_assert_v1" or reuse.get("parallel_adr_engine_forbidden") is not True or reuse.get("parallel_decision_context_store_forbidden") is not True: raise ContractError("A5_REUSE")
    ed=o.get("existing_decision_resolution",{})
    if ed.get("lookup_order")!=["DECISION_CONTEXT_ASOF@CURRENT","public.lf_decision_log","transversal.decision_log"]: raise ContractError("A5_EXISTING_DECISION_LOOKUP")
    for k in ("exact_subject_and_scope_match_required","currentness_required","current_existing_decision_must_be_reused","duplicate_human_decision_request_forbidden","historical_or_superseded_decision_does_not_satisfy_currentness","no_matching_current_decision_allows_new_question_only_after_evidence_sufficiency_check"):
        if ed.get(k) is not True: raise ContractError("A5_EXISTING_DECISION_"+k)
    hr=o.get("human_decision_routing",{})
    if hr.get("route_only_when")!="TRUE_OWNER_DECISION_AFTER_RESOLVABLE_EVIDENCE_PATHS_EXHAUSTED" or hr.get("owner_scope")!="SUPER_ADMIN" or hr.get("packet_schema_version")!="ANALYSIS_HUMAN_DECISION_PACKET_V1": raise ContractError("A5_HUMAN_ROUTING_IDENTITY")
    req_packet={"decision_code","scope_refs[]","material_question","options[]","recommendation","risk_if_deferred","authority_refs[]","evidence_refs[]","currentness_refs[]","owner_scope","resume_condition","status"}
    if set(hr.get("required_packet_fields",[]))!=req_packet or set(hr.get("status_values",[]))!={"PENDING_OWNER_DECISION","RESOLVED"}: raise ContractError("A5_HUMAN_ROUTING_PACKET")
    for k in ("recommendation_required","options_required","pending_packet_must_be_exposed_in_a9_output","pending_packet_must_not_be_hidden_inside_generic_blockers","resolvable_evidence_gap_must_not_be_routed_to_human","missing_implementation_alone_must_not_be_routed_to_human","programming_strategy_choice_must_not_be_routed_to_human"):
        if hr.get(k) is not True: raise ContractError("A5_HUMAN_ROUTING_"+k)
    if o.get("no_parallel_engine") is not True or o.get("runtime_activation") is not False or o.get("production_activation") is not False: raise ContractError("A5_ACTIVATION")

def validate_material_front_coverage(o):
    if o.get("schema_version")!="ANALYSIS_MATERIAL_FRONT_COVERAGE_CONTRACT_V1": raise ContractError("MFC_VERSION")
    if o.get("producer_unit")!="A7" or set(o.get("consumer_units",[]))!={"A9"}: raise ContractError("MFC_BOUNDARY")
    if set(o.get("input_contracts",[]))!={"SHARED_CHANGE_IMPACT_ANALYSIS","ANALYSIS_IMPLEMENTATION_DRAFT","RISK_AND_QUALITY_SIGNALS"}: raise ContractError("MFC_INPUTS")
    if o.get("output_contract")!="MATERIAL_FRONT_COVERAGE_V1": raise ContractError("MFC_OUTPUT")
    d=o.get("front_discovery",{})
    if d.get("front_kind_policy")!="EVIDENCE_DERIVED_OPEN_CATALOG" or d.get("closed_static_front_catalog_forbidden") is not True: raise ContractError("MFC_OPEN_CATALOG")
    if d.get("domain_name_only_selection_forbidden") is not True: raise ContractError("MFC_DOMAIN_SELECTION")
    required_sources={"target_granularity","change_classification","direct_impacts[]","indirect_impacts[]","consumers[]","dependency_paths[]","requirements[]","authority_bindings[]","applicable_invariants[]","risk_and_quality_signals[]","specialist_outputs[]","unresolved_material_gaps[]"}
    if set(d.get("candidate_derivation_sources",[]))!=required_sources: raise ContractError("MFC_DERIVATION_SOURCES")
    fc=o.get("front_contract",{})
    if set(fc.get("status_values",[]))!={"REQUIRED","REUSE_AS_IS","NOT_APPLICABLE"}: raise ContractError("MFC_STATUS_VALUES")
    if set(fc.get("closure_values",[]))!={"CLOSED","BLOCKED"}: raise ContractError("MFC_CLOSURE_VALUES")
    required_fields={"front_id","front_kind","status","closure","source_signal_refs[]","scope_refs[]","authority_refs[]","evidence_refs[]","currentness_refs[]","blockers[]","reason"}
    if set(fc.get("required_fields",[]))!=required_fields: raise ContractError("MFC_FIELDS")
    g=o.get("coverage_guards",{})
    required_true={"every_material_candidate_emitted_exactly_once","silent_omission_forbidden","unknown_material_signal_requires_blocked_front","required_front_requires_scope_binding","required_closed_front_requires_material_evidence","reuse_as_is_requires_currentness","not_applicable_requires_evidence_and_reason","unmapped_material_signals_must_be_explicit","absence_never_means_not_applicable"}
    for k in required_true:
        if g.get(k) is not True: raise ContractError("MFC_GUARD_"+k)
    outputs={"front_candidate_refs[]","material_fronts[]","unmapped_material_signals[]","all_material_fronts_accounted","coverage_fingerprint_sha256","source_refs[]","currentness_refs[]"}
    if set(o.get("output_requirements",[]))!=outputs: raise ContractError("MFC_OUTPUT_REQUIREMENTS")
    ib=o.get("integration_boundary",{})
    if ib.get("a9_must_preserve_full_artifact") is not True or ib.get("programming_context_snapshot_field")!="material_front_coverage": raise ContractError("MFC_A9_INTEGRATION")
    if ib.get("scope_readiness_is_separate_dimension") is not True or ib.get("stop_rule_policy_change_owned_by")!="A8" or ib.get("no_stop_rule_change_in_this_contract") is not True: raise ContractError("MFC_MICROLOT_BOUNDARY")
    bs=o.get("blocker_semantics",{})
    for k in ("implementation_absence_alone_is_not_analysis_blocker","implementation_new_with_resolved_authority_requirements_and_acceptance_is_build_required","required_closed_front_may_represent_downstream_build_obligation","missing_code_table_binding_or_adapter_if_programmable_is_not_blocker","blocker_reason_must_identify_unresolved_material_authority_not_implementation_absence"):
        if bs.get(k) is not True: raise ContractError("MFC_BLOCKER_SEMANTICS_"+k)
    allowed_blockers={"AUTHORITY_UNRESOLVED","OWNER_DECISION_REQUIRED","CONTRACT_UNRESOLVED","CURRENTNESS_UNRESOLVED","MATERIAL_CONTRADICTION","EXTERNAL_DEPENDENCY_UNAVAILABLE"}
    if set(bs.get("blocked_front_requires_one_of",[]))!=allowed_blockers: raise ContractError("MFC_BLOCKER_SEMANTICS_ALLOWED")
    if o.get("no_parallel_engine") is not True or o.get("runtime_activation") is not False or o.get("production_activation") is not False: raise ContractError("MFC_ACTIVATION")

def validate_analysis_stop_rule(o):
    if o.get("schema_version")!="ANALYSIS_STOP_RULE_CONTRACT_V1" or o.get("unit")!="A8": raise ContractError("STOP_RULE_IDENTITY")
    if set(o.get("input_contracts",[]))!={"TARGETED_EVIDENCE_SET_V1","DECISION_CONTEXT","MATERIAL_FRONT_COVERAGE_V1"}: raise ContractError("STOP_RULE_INPUTS")
    if o.get("output_contract")!="ANALYSIS_STOP_RULE_V1": raise ContractError("STOP_RULE_OUTPUT")
    d=o.get("decision",{})
    if set(d.get("values",[]))!={"STOP","CONTINUE","REQUIRES_DECISION","BLOCKED"}: raise ContractError("STOP_RULE_VALUES")
    required_stop={"decision_stable=true","all_material_fronts_accounted=true","unresolved_decision_changing_questions[]=empty","additional_available_evidence_capable_of_changing_material_decision[]=empty"}
    if set(d.get("stop_requires",[]))!=required_stop: raise ContractError("STOP_RULE_REQUIREMENTS")
    if d.get("fronts_accounted_does_not_require_all_fronts_closed") is not True or d.get("blocked_or_decision_required_fronts_may_remain_explicit") is not True: raise ContractError("STOP_RULE_FRONT_SEMANTICS")
    if d.get("missing_material_front_forbids_stop") is not True or d.get("stable_decision_with_incomplete_front_coverage_forbids_stop") is not True or d.get("front_coverage_complete_with_unstable_decision_forbids_stop") is not True: raise ContractError("STOP_RULE_FAIL_CLOSED")
    required_fields={"decision","decision_stable","material_front_coverage_ref","all_material_fronts_accounted","unresolved_decision_changing_questions[]","additional_available_evidence_capable_of_changing_material_decision[]","evidence_refs[]","reason"}
    if set(o.get("required_fields",[]))!=required_fields: raise ContractError("STOP_RULE_FIELDS")
    cp=o.get("continuation_policy",{})
    if cp.get("continue_only_for_material_evidence") is not True or cp.get("no_curiosity_search") is not True or cp.get("no_duplicate_read") is not True or cp.get("no_full_scan_without_material_trigger") is not True: raise ContractError("STOP_RULE_CONTINUATION")
    ib=o.get("integration_boundary",{})
    if ib.get("consumer_unit")!="A9" or ib.get("programming_context_snapshot_field")!="analysis_stop_rule" or ib.get("material_front_coverage_contract")!="MATERIAL_FRONT_COVERAGE_V1": raise ContractError("STOP_RULE_A9_INTEGRATION")
    if ib.get("scope_readiness_policy_unchanged_in_this_microlot") is not True: raise ContractError("STOP_RULE_MICROLOT_BOUNDARY")
    hr=o.get("human_decision_routing_guard",{})
    for k in ("requires_decision_before_stop_must_have_human_packet","human_packet_owner_scope_required","duplicate_owner_decision_request_forbidden","resolvable_evidence_gap_must_not_route_human","missing_implementation_must_not_route_human","stop_may_preserve_pending_owner_decision_only_if_packet_is_exposed"):
        if hr.get(k) is not True: raise ContractError("STOP_RULE_HUMAN_ROUTING_"+k)
    if o.get("no_parallel_engine") is not True or o.get("runtime_activation") is not False or o.get("production_activation") is not False: raise ContractError("STOP_RULE_ACTIVATION")

def validate_analysis_implementability(o):
    if o.get("schema_version")!="ANALYSIS_IMPLEMENTABILITY_CONTRACT_V1" or o.get("producer_unit")!="A6": raise ContractError("IMPLEMENTABILITY_IDENTITY")
    if set(o.get("consumer_units",[]))!={"A9"} or o.get("output_contract")!="IMPLEMENTABILITY_SCHEMA_V1": raise ContractError("IMPLEMENTABILITY_BOUNDARY")
    rc=o.get("requirement_contract",{})
    if set(rc.get("obligation_modes",[]))!={"MUST_PRESERVE_EXACT","MUST_PRESERVE_SEMANTICS","RESOLVE_BEFORE_USE","INFORMATIVE"}: raise ContractError("IMPLEMENTABILITY_OBLIGATION_MODES")
    if set(rc.get("side_effect_classes",[]))!={"NONE","READ","WRITE","EXTERNAL_EFFECT","MIXED","UNKNOWN"}: raise ContractError("IMPLEMENTABILITY_SIDE_EFFECT_CLASSES")
    req_fields={"requirement_id","scope_refs[]","outcome","obligation_mode","authority_refs[]","evidence_refs[]","currentness_refs[]","input_contract_refs[]","output_contract_refs[]","state_contract_refs[]","error_behavior_refs[]","permission_refs[]","side_effect_class","preconditions[]","blockers[]","acceptance_signals[]"}
    if set(rc.get("required_fields",[]))!=req_fields or rc.get("explicit_empty_arrays_required_when_not_applicable") is not True: raise ContractError("IMPLEMENTABILITY_REQUIREMENT_FIELDS")
    bc=o.get("binding_contract",{})
    if bc.get("binding_kind_policy")!="EVIDENCE_DERIVED_OPEN_CATALOG": raise ContractError("IMPLEMENTABILITY_BINDING_KIND_POLICY")
    binding_fields={"binding_id","scope_refs[]","binding_kind","canonical_ref","resolved_current_value","value_transport","currentness_ref","resolver_ref","implementation_obligation","evidence_refs[]","blockers[]"}
    if set(bc.get("required_fields",[]))!=binding_fields: raise ContractError("IMPLEMENTABILITY_BINDING_FIELDS")
    if set(bc.get("value_transport_values",[]))!={"INLINE_RESOLVED_VALUE_PLUS_CANONICAL_REF","EXACT_REF_ONLY","EXACT_REF_PLUS_TYPED_RESOLVER"}: raise ContractError("IMPLEMENTABILITY_TRANSPORT_VALUES")
    if bc.get("canonical_ref_is_authority") is not True or bc.get("resolved_literal_may_not_replace_canonical_ref") is not True or bc.get("typed_resolver_required_when_resolution_deferred") is not True: raise ContractError("IMPLEMENTABILITY_BINDING_AUTHORITY")
    g=o.get("completeness_guards",{})
    required_true={"material_requirement_without_authority_or_explicit_blocker_forbidden","material_permission_unknown_requires_blocker","material_side_effect_unknown_requires_blocker","applicable_state_behavior_must_be_explicit_or_blocked","applicable_error_behavior_must_be_explicit_or_blocked","applicable_input_output_contracts_must_be_explicit_or_blocked","silent_material_field_omission_forbidden"}
    for k in required_true:
        if g.get(k) is not True: raise ContractError("IMPLEMENTABILITY_GUARD_"+k)
    sb=o.get("strategy_boundary",{})
    forbidden={"chosen_component_structure","chosen_framework_pattern","chosen_endpoint_design","chosen_internal_algorithm","chosen_state_management_library"}
    if sb.get("technical_strategy_owned_by")!="PG-03" or set(sb.get("forbidden_fields",[]))!=forbidden or sb.get("analysis_specifies_what_not_how") is not True: raise ContractError("IMPLEMENTABILITY_STRATEGY_BOUNDARY")
    outputs={"requirements[]","canonical_implementation_bindings[]","unresolved_material_items[]","source_refs[]","currentness_refs[]","implementability_fingerprint_sha256"}
    if set(o.get("output_requirements",[]))!=outputs: raise ContractError("IMPLEMENTABILITY_OUTPUTS")
    ib=o.get("integration_boundary",{})
    if ib.get("a9_must_preserve_full_artifact") is not True or ib.get("programming_context_snapshot_field")!="implementability_schema" or ib.get("receiver_parity_policy_owned_by_next_boundary") is not True: raise ContractError("IMPLEMENTABILITY_INTEGRATION")
    if o.get("no_parallel_engine") is not True or o.get("runtime_activation") is not False or o.get("production_activation") is not False: raise ContractError("IMPLEMENTABILITY_ACTIVATION")

def validate_handoff_parity(o):
    if o.get("schema_version")!="ANALYSIS_PROGRAMMING_HANDOFF_PARITY_CONTRACT_V1": raise ContractError("HANDOFF_PARITY_VERSION")
    if o.get("producer_unit")!="A9" or o.get("consumer_unit")!="PG-01": raise ContractError("HANDOFF_PARITY_BOUNDARY")
    ss=o.get("shared_snapshot_contract",{})
    if ss.get("schema_version")!="PROGRAMMING_CONTEXT_SNAPSHOT_V1" or ss.get("contract_ref")!="programming_entry_contract_v1.json#programming_context_snapshot": raise ContractError("HANDOFF_PARITY_SHARED_SCHEMA")
    if ss.get("shared_schema_digest_required") is not True or ss.get("parallel_receiver_schema_forbidden") is not True: raise ContractError("HANDOFF_PARITY_SHARED_SCHEMA_GUARDS")
    p=o.get("producer_requirements",{})
    required_paths={"target","target_granularity","authority_state","implementation_state","implementability_schema","material_front_coverage","analysis_stop_rule","scope_readiness[]","package_readiness","authority_fingerprint_sha256","source_snapshot_sha256"}
    if p.get("snapshot_schema_digest_sha256_required") is not True or p.get("full_material_payload_required") is not True or set(p.get("material_paths",[]))!=required_paths: raise ContractError("HANDOFF_PARITY_PRODUCER")
    ps=o.get("persistence_requirements",{})
    if ps.get("context_id_required") is not True or ps.get("context_sha256_required") is not True or ps.get("exact_recorded_context_required") is not True or ps.get("latest_mutable_reinterpretation_forbidden") is not True: raise ContractError("HANDOFF_PARITY_PERSISTENCE")
    rr=o.get("receiver_requirements",{})
    if rr.get("resolve_exact_context_id") is not True or rr.get("recompute_context_sha256") is not True or rr.get("context_sha256_must_match_receipt") is not True or rr.get("receiver_schema_digest_must_match_producer_schema_digest") is not True or rr.get("all_material_paths_must_validate") is not True: raise ContractError("HANDOFF_PARITY_RECEIVER")
    if rr.get("unknown_material_field_policy")!="BLOCK" or rr.get("missing_material_field_policy")!="BLOCK" or rr.get("lossy_material_projection_forbidden") is not True: raise ContractError("HANDOFF_PARITY_RECEIVER_FAIL_CLOSED")
    pp=o.get("projection_policy",{})
    if pp.get("worker_projection_after_parity_only") is not True or pp.get("minimum_relevant_subset_allowed") is not True or pp.get("projection_must_preserve_source_refs") is not True or pp.get("projection_must_preserve_material_semantics") is not True or pp.get("projection_digest_required") is not True or pp.get("upstream_snapshot_mutation_forbidden") is not True: raise ContractError("HANDOFF_PARITY_PROJECTION")
    rec=o.get("receipt",{})
    if rec.get("schema_version")!="PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1": raise ContractError("HANDOFF_PARITY_RECEIPT_VERSION")
    receipt_fields={"context_id","context_sha256","snapshot_schema_digest_sha256","receiver_schema_digest_sha256","material_projection_sha256","validated_material_paths[]","verdict"}
    if set(rec.get("required_fields",[]))!=receipt_fields or set(rec.get("verdict_values",[]))!={"ACCEPT","BLOCK"}: raise ContractError("HANDOFF_PARITY_RECEIPT")
    if o.get("no_parallel_engine") is not True or o.get("runtime_activation") is not False or o.get("production_activation") is not False: raise ContractError("HANDOFF_PARITY_ACTIVATION")

def validate_testing_admission(o):
    if o.get("schema_version")!="TESTING_ADMISSION_CONTRACT_V1": raise ContractError("TESTING_ADMISSION_VERSION")
    m=o.get("modes",{})
    if set(m)!={"DESIGN_ONLY","EXECUTION"}: raise ContractError("TESTING_MODES")
    for mode in m.values():
        if mode.get("agent_task_required") is not False or mode.get("story_required") is not False: raise ContractError("TESTING_STAGE_COUPLING")
    if "frozen_candidate_ref" in m["DESIGN_ONLY"].get("requires",[]): raise ContractError("DESIGN_MODE_CANDIDATE_REQUIRED")
    if set(m["DESIGN_ONLY"].get("forbids",[]))!={"frozen_candidate_ref","frozen_candidate_sha256"}: raise ContractError("DESIGN_MODE_FORBIDS")
    for k in ("frozen_candidate_ref","frozen_candidate_sha256"):
        if k not in m["EXECUTION"].get("requires",[]): raise ContractError("EXECUTION_MODE_CANDIDATE_MISSING")
    if o.get("no_parallel_engine") is not True: raise ContractError("TESTING_PARALLEL_ENGINE")

def classify_analysis_depth_v1(signals):
    required={"materiality_level","scope_bounded","authority_state","reversibility_state","currentness_decision","material_contradiction","known_cross_scope_impact","unresolved_material_signal_count","required_specialist_count"}
    if set(signals)!=required: raise ContractError("A2_DEPTH_SIGNAL_KEYS")
    materiality=signals["materiality_level"]
    scope=signals["scope_bounded"]
    authority=signals["authority_state"]
    reversibility=signals["reversibility_state"]
    currentness=signals["currentness_decision"]
    contradiction=signals["material_contradiction"]
    cross_scope=signals["known_cross_scope_impact"]
    unresolved=signals["unresolved_material_signal_count"]
    specialists=signals["required_specialist_count"]
    if materiality not in {"LOW","MEDIUM","HIGH","UNKNOWN"}: raise ContractError("A2_DEPTH_SIGNAL_MATERIALITY")
    if scope not in {"TRUE","FALSE","UNKNOWN"}: raise ContractError("A2_DEPTH_SIGNAL_SCOPE")
    if authority not in {"SUFFICIENT","INSUFFICIENT","UNKNOWN"}: raise ContractError("A2_DEPTH_SIGNAL_AUTHORITY")
    if reversibility not in {"DEMONSTRATED","NOT_DEMONSTRATED","UNKNOWN"}: raise ContractError("A2_DEPTH_SIGNAL_REVERSIBILITY")
    if currentness not in {"CURRENT","CURRENT_REBOUND","STALE_AFFECTED","UNKNOWN_FAIL_CLOSED","UNRESOLVED"}: raise ContractError("A2_DEPTH_SIGNAL_CURRENTNESS")
    if not isinstance(contradiction,bool): raise ContractError("A2_DEPTH_SIGNAL_CONTRADICTION")
    if cross_scope not in {True,False,"UNKNOWN"}: raise ContractError("A2_DEPTH_SIGNAL_CROSS_SCOPE")
    if isinstance(unresolved,bool) or not isinstance(unresolved,int) or unresolved<0: raise ContractError("A2_DEPTH_SIGNAL_UNRESOLVED")
    if isinstance(specialists,bool) or not isinstance(specialists,int) or specialists<0: raise ContractError("A2_DEPTH_SIGNAL_SPECIALISTS")
    if (
        materiality=="HIGH"
        or scope=="FALSE"
        or authority=="INSUFFICIENT"
        or currentness=="STALE_AFFECTED"
        or contradiction is True
        or cross_scope is True
    ):
        return "L3"
    if (
        materiality in {"MEDIUM","UNKNOWN"}
        or scope=="UNKNOWN"
        or authority=="UNKNOWN"
        or reversibility in {"NOT_DEMONSTRATED","UNKNOWN"}
        or currentness in {"CURRENT_REBOUND","UNKNOWN_FAIL_CLOSED","UNRESOLVED"}
        or cross_scope=="UNKNOWN"
        or unresolved>0
        or specialists>0
    ):
        return "L2"
    if (
        materiality=="LOW"
        and scope=="TRUE"
        and authority=="SUFFICIENT"
        and reversibility=="DEMONSTRATED"
        and currentness=="CURRENT"
        and contradiction is False
        and cross_scope is False
        and unresolved==0
        and specialists==0
    ):
        return "L1"
    raise ContractError("A2_DEPTH_UNCOVERED_STATE")

def validate_analysis_change_classification(o):
    if o.get("schema_version")!="ANALYSIS_CHANGE_CLASSIFICATION_CONTRACT_V1" or o.get("unit")!="A2": raise ContractError("A2_IDENTITY")
    c=o.get("classification",{})
    if c.get("depth_levels")!=["L1","L2","L3"]: raise ContractError("A2_DEPTH_LEVELS")
    if c.get("change_type_required") is not True or c.get("change_type_policy")!="EVIDENCE_DERIVED_OPEN_CATALOG": raise ContractError("A2_CHANGE_TYPE")
    if c.get("target_granularity_required") is not True or c.get("target_granularity_policy")!="EVIDENCE_DERIVED_OPEN_CATALOG": raise ContractError("A2_TARGET_GRANULARITY")
    hints={"APP","SHELL","MODULE","SCREEN","SECTION","CONTROL","RULE","API","DATA","WORKFLOW","OTHER"}
    if not hints.issubset(set(c.get("target_granularity_hints",[]))): raise ContractError("A2_TARGET_GRANULARITY_HINTS")
    if c.get("nested_target_parent_ref_required") is not True: raise ContractError("A2_NESTED_PARENT")
    if c.get("implementation_state_inference_forbidden") is not True: raise ContractError("A2_IMPLEMENTATION_STATE_INFERENCE")
    if c.get("depth_reason_required") is not True or c.get("evidence_refs_required") is not True: raise ContractError("A2_REPRODUCIBILITY")
    dp=c.get("depth_policy",{})
    if dp.get("schema_version")!="ANALYSIS_DEPTH_POLICY_V1" or dp.get("policy_kind")!="MONOTONIC_PRECEDENCE_NO_WEIGHTS": raise ContractError("A2_DEPTH_POLICY_IDENTITY")
    expected_signal_sets={
        "materiality_level":{"LOW","MEDIUM","HIGH","UNKNOWN"},
        "scope_bounded":{"TRUE","FALSE","UNKNOWN"},
        "authority_state":{"SUFFICIENT","INSUFFICIENT","UNKNOWN"},
        "reversibility_state":{"DEMONSTRATED","NOT_DEMONSTRATED","UNKNOWN"},
        "currentness_decision":{"CURRENT","CURRENT_REBOUND","STALE_AFFECTED","UNKNOWN_FAIL_CLOSED","UNRESOLVED"},
    }
    for key,vals in expected_signal_sets.items():
        if set(dp.get("signals",{}).get(key,[]))!=vals: raise ContractError("A2_DEPTH_POLICY_SIGNAL_"+key)
    if dp.get("signals",{}).get("material_contradiction")!="BOOLEAN": raise ContractError("A2_DEPTH_POLICY_CONTRADICTION")
    if dp.get("signals",{}).get("known_cross_scope_impact")!="BOOLEAN_OR_UNKNOWN": raise ContractError("A2_DEPTH_POLICY_CROSS_SCOPE")
    if dp.get("signals",{}).get("unresolved_material_signal_count")!="NON_NEGATIVE_INTEGER" or dp.get("signals",{}).get("required_specialist_count")!="NON_NEGATIVE_INTEGER": raise ContractError("A2_DEPTH_POLICY_COUNTS")
    if dp.get("precedence")!=["L3_EXPLICIT_HIGH_RISK","L2_MEDIUM_OR_UNPROVEN","L1_FULLY_BOUNDED_LOW_RISK"]: raise ContractError("A2_DEPTH_POLICY_PRECEDENCE")
    if dp.get("unknown_material_never_L1") is not True or dp.get("worsening_signal_cannot_reduce_depth") is not True: raise ContractError("A2_DEPTH_POLICY_MONOTONIC")
    if dp.get("depth_is_execution_permission") is not False or dp.get("readiness_and_admission_remain_separate") is not True: raise ContractError("A2_DEPTH_POLICY_AUTHORITY")
    if dp.get("case_family_hardcoding_forbidden") is not True or dp.get("arbitrary_weights_forbidden") is not True: raise ContractError("A2_DEPTH_POLICY_NO_OVERFIT")
    s=o.get("specialist_resolution",{})
    expected={"cardinality":"0..N","selector_capability":"CAPABILITY_SELECTOR","selector_version_policy":"CURRENT","currentness_required":True,"release_state_required":"RELEASED","hardcoded_specialist_identity_forbidden":True,"hardcoded_story_creator_forbidden":True,"selection_is_execution_permission":False}
    for k,v in expected.items():
        if s.get(k)!=v: raise ContractError("A2_SPECIALIST_"+k)
    if s.get("catalog_source")!="CURRENT_RELEASED_CAPABILITY_MANIFESTS_WITH_SPECIALIST_DECLARATION": raise ContractError("A2_SPECIALIST_CATALOG")
    if o.get("no_parallel_engine") is not True: raise ContractError("A2_PARALLEL_ENGINE")

def validate_analysis_targeted_evidence(o):
    if o.get("schema_version")!="ANALYSIS_TARGETED_EVIDENCE_CONTRACT_V1" or o.get("unit")!="A3": raise ContractError("A3_IDENTITY")
    a=o.get("acquisition",{})
    expected={"capability":"TARGETED_EVIDENCE_ACQUISITION","source_resolution":"SOURCE_RESOLUTION_POLICY","data_access":"TYPED_DATA_ACCESS","query_only_missing_or_material_evidence":True,"reuse_current_evidence_before_fetch":True,"duplicate_read_forbidden":True,"full_repository_search_without_trigger_forbidden":True,"stop_when":"MINIMUM_SUFFICIENT_CONTEXT_REACHED"}
    for k,v in expected.items():
        if a.get(k)!=v: raise ContractError("A3_ACQUISITION_"+k)
    allowed={"REQUIRED_EVIDENCE_MISSING","MATERIAL_CONTRADICTION","CURRENTNESS_UNPROVEN","SOURCE_DRIFT"}
    if set(a.get("continue_only_if",[]))!=allowed: raise ContractError("A3_CONTINUE_GATES")
    tr=o.get("target_resolution",{})
    if tr.get("required_when_target_hints_present") is not True or tr.get("target_granularity_required") is not True: raise ContractError("A3_TARGET_RESOLUTION_REQUIRED")
    dims=tr.get("state_dimensions",{})
    if set(dims.get("authority_state",[]))!={"EXISTING","NEW","UNKNOWN"} or set(dims.get("implementation_state",[]))!={"EXISTING","NEW","UNKNOWN"}: raise ContractError("A3_STATE_DIMENSIONS")
    if set(tr.get("authority_existing_requires",[]))!={"exact_target_ref","authority_currentness_ref","authority_refs[]"}: raise ContractError("A3_AUTHORITY_EXISTING")
    if set(tr.get("authority_new_requires",[]))!={"negative_canonical_authority_evidence[]","canonical_search_scope[]","new_authority_reason"}: raise ContractError("A3_AUTHORITY_NEW")
    if set(tr.get("implementation_existing_requires",[]))!={"implementation_refs[]","implementation_currentness_refs[]","as_is_consumers[]","as_is_dependencies[]","explicit_delta"}: raise ContractError("A3_IMPLEMENTATION_EXISTING")
    if set(tr.get("implementation_new_requires",[]))!={"negative_current_implementation_evidence[]","reuse_search_scope[]","reuse_candidates_evaluated[]","authority_refs_or_explicit_gaps[]"}: raise ContractError("A3_IMPLEMENTATION_NEW")
    if tr.get("authority_existing_implementation_new_allowed") is not True or tr.get("authority_state_does_not_imply_implementation_state") is not True: raise ContractError("A3_STATE_INDEPENDENCE")
    if tr.get("implementation_existing_greenfield_redefinition_forbidden") is not True or tr.get("implementation_existing_delta_required_downstream") is not True: raise ContractError("A3_BROWNFIELD_IMPLEMENTATION")
    if tr.get("unknown_dimension_behavior")!="NEED_MORE_EVIDENCE_OR_REQUIRES_DECISION": raise ContractError("A3_UNKNOWN_DIMENSION")
    if tr.get("technical_solution_selection_deferred_to_programming") is not True: raise ContractError("A3_STRATEGY_BOUNDARY")
    if tr.get("no_parallel_asset_resolver") is not True: raise ContractError("A3_PARALLEL_TARGET_RESOLVER")
    d=o.get("design_authority_evidence",{})
    if d.get("canonical_ref_is_authority") is not True or d.get("resolved_current_value_may_accompany_ref") is not True or d.get("resolved_literal_must_not_replace_canonical_ref") is not True: raise ContractError("A3_DESIGN_AUTHORITY")
    if d.get("physical_asset_resolution_required_when_material") is not True or d.get("binding_decision_owned_by")!="A6": raise ContractError("A3_DESIGN_BINDING_OWNER")
    required_outputs={"evidence_items[]","source_refs[]","currentness_refs[]","target_granularity","authority_state","implementation_state","target_resolution","authority_binding_refs[]","as_is_baseline_or_new_implementation_evidence","unresolved_material_gaps[]","sufficiency_verdict"}
    if set(o.get("output_requirements",[]))!=required_outputs: raise ContractError("A3_OUTPUTS")
    if o.get("no_over_search") is not True or o.get("no_parallel_engine") is not True: raise ContractError("A3_SEARCH_GOVERNANCE")
    if set(o.get("sufficiency_verdicts",[]))!={"SUFFICIENT","NEED_MORE_EVIDENCE","REQUIRES_DECISION","BLOCKED"}: raise ContractError("A3_VERDICTS")

def validate_shared_impact(o):
    if o.get("schema_version")!="SHARED_CHANGE_IMPACT_ANALYSIS_CONTRACT_V1": raise ContractError("IMPACT_VERSION")
    if set(o.get("units",[]))!={"A4","TST-05"}: raise ContractError("IMPACT_UNITS")
    if o.get("provider")!="SHARED_CHANGE_IMPACT_ANALYSIS" or o.get("transformation_action")!="TRANSVERSALIZE_EXISTING_CORE": raise ContractError("IMPACT_PROVIDER")
    required_sources={"LF_GLOBAL_TECHNICAL_INVENTORY_V1","inventory.fn_impact_analysis_v1","inventory.fn_dependencies_v1","IG_CURATOR_VALIDATOR_REFACTOR_V2:M7.11"}
    if set(o.get("sources",[]))!=required_sources: raise ContractError("IMPACT_SOURCES")
    required_outputs={"direct_impacts[]","indirect_impacts[]","consumers[]","dependency_paths[]","evidence_refs[]","unresolved_material_impacts[]"}
    if set(o.get("core_output_requirements",[]))!=required_outputs: raise ContractError("IMPACT_OUTPUTS")
    tp=o.get("testing_projection",{})
    if tp.get("consumes_same_core") is not True or tp.get("parallel_impact_engine_forbidden") is not True: raise ContractError("IMPACT_TESTING_REUSE")
    if o.get("consumer_migration_policy")!="KEEP_EXISTING_CONSUMERS_AS_ADAPTERS_UNTIL_QUALIFIED_CUTOVER": raise ContractError("IMPACT_CUTOVER")
    if o.get("runtime_activation") is not False or o.get("production_activation") is not False or o.get("no_parallel_engine") is not True: raise ContractError("IMPACT_ACTIVATION")

def validate_testing_pipeline(o):
    if o.get("schema_version")!="TESTING_WAVE1_DESIGN_PIPELINE_CONTRACT_V1": raise ContractError("TEST_PIPELINE_VERSION")
    if set(o.get("units",[]))!={"TST-02","TST-03","TST-04"} or o.get("sequence")!=["TST-02","TST-03","TST-04"]: raise ContractError("TEST_PIPELINE_SEQUENCE")
    if o.get("story_required") is not False or o.get("agent_task_required") is not False: raise ContractError("TEST_PIPELINE_STAGE_COUPLING")
    steps=o.get("steps",{})
    if set(steps)!={"TST-02","TST-03","TST-04"}: raise ContractError("TEST_PIPELINE_STEPS")
    if steps["TST-02"].get("output_contract")!="TEST_CHANGE_SIGNALS_V1": raise ContractError("TST02_OUTPUT")
    if steps["TST-03"].get("input_contracts")!=["TEST_CHANGE_SIGNALS_V1"] or steps["TST-03"].get("output_contract")!="TEST_RISK_ASSESSMENT_V1": raise ContractError("TST03_CHAIN")
    if steps["TST-04"].get("input_contracts")!=["TEST_RISK_ASSESSMENT_V1"] or steps["TST-04"].get("output_contract")!="TEST_QUALITY_OBJECTIVES_V1": raise ContractError("TST04_CHAIN")
    for u in ("TST-02","TST-03","TST-04"):
        if "public.lf_strategy_test_characteristic_catalog" not in steps[u].get("mapped_assets",[]): raise ContractError(u+"_QUALITY_CATALOG")
    if o.get("no_parallel_engine") is not True: raise ContractError("TEST_PIPELINE_PARALLEL_ENGINE")

def validate_manifest(o):
    if o.get("schema_version")!="PROGRAMMING_AGENT_WAVE1_BOUNDARY_MANIFEST_V1": raise ContractError("MANIFEST_VERSION")
    if o.get("state")!="SOURCE_ONLY_CANDIDATE": raise ContractError("MANIFEST_STATE")
    if not SHA40.fullmatch(o.get("base_main_sha","")): raise ContractError("MANIFEST_BASE_SHA")
    scope={"A1","A2","A3","A4","A5","PG-01","TST-01","TST-02","TST-03","TST-04","TST-05"}
    if set(o.get("scope",[]))!=scope: raise ContractError("MANIFEST_SCOPE")
    contracts=o.get("contracts",{})
    if set(contracts)!=scope: raise ContractError("MANIFEST_CONTRACT_MAP")
    if contracts.get("A4")!=contracts.get("TST-05"): raise ContractError("MANIFEST_SHARED_IMPACT_SPLIT")
    if len({contracts.get("TST-02"),contracts.get("TST-03"),contracts.get("TST-04")})!=1: raise ContractError("MANIFEST_TEST_PIPELINE_SPLIT")

def validate_analysis_package(o):
    if o.get("schema_version")!="ANALYSIS_IMPLEMENTATION_PACKAGE_CONTRACT_V1" or o.get("unit")!="A9": raise ContractError("A9_PACKAGE_IDENTITY")
    if o.get("output_contract")!="ANALYSIS_IMPLEMENTATION_PACKAGE_V1": raise ContractError("A9_PACKAGE_OUTPUT")
    required={"request_identity","change_classification","research_context","impact_map","decision_context","requirements","specialist_results","invariants_risk_quality","hard_boundaries","implementation_preconditions","interfaces_payloads_states_errors","acceptance_obligations","reversibility","source_currentness","evidence_refs","typed_blockers","analysis_verdict"}
    if set(o.get("required_sections",[]))!=required: raise ContractError("A9_PACKAGE_SECTIONS")
    a=o.get("assembly_policy",{})
    for k in ("single_canonical_spec","section_index_required","stable_item_ids_required","dependency_graph_required","full_repo_payload_forbidden","mega_unindexed_payload_forbidden","lossless_provenance_required","programming_task_partition_forbidden_in_analysis","test_case_construction_forbidden"):
        if a.get(k) is not True: raise ContractError("A9_PACKAGE_ASSEMBLY_"+k)
    d=o.get("decision_visibility",{})
    if d.get("human_decision_packets_source")!="decision_context.human_decision_routing": raise ContractError("A9_HUMAN_DECISION_SOURCE")
    for k in ("pending_owner_decisions_must_be_rendered_as_dedicated_section","pending_owner_decisions_must_include_question_options_recommendation_owner_and_risk","generic_blocker_only_representation_forbidden","zero_pending_decisions_must_be_explicit"):
        if d.get(k) is not True: raise ContractError("A9_HUMAN_DECISION_"+k)
    q=o.get("qualification",{})
    if set(q.get("verdict_values",[]))!={"READY","PARTIAL_READY","NEED_MORE_EVIDENCE","REQUIRES_DECISION","BLOCKED"}: raise ContractError("A9_PACKAGE_VERDICTS")
    for k in ("ready_forbids_pending_material_owner_decision","partial_ready_may_preserve_pending_decisions_only_outside_admitted_ready_scopes","missing_implementation_alone_must_not_force_blocked","all_material_fronts_accounted_required","scope_front_consistency_required"):
        if q.get(k) is not True: raise ContractError("A9_PACKAGE_QUALIFICATION_"+k)
    sb=o.get("snapshot_boundary",{})
    if sb.get("snapshot_contract")!="PROGRAMMING_CONTEXT_SNAPSHOT_V1" or sb.get("persist_append_only") is not True: raise ContractError("A9_SNAPSHOT_BOUNDARY")
    for k in ("preserve_decision_context_losslessly","preserve_human_decision_packets_losslessly","preserve_material_front_coverage_losslessly","preserve_implementability_losslessly","preserve_scope_readiness_losslessly"):
        if sb.get(k) is not True: raise ContractError("A9_SNAPSHOT_"+k)
    if o.get("runtime_activation") is not False or o.get("production_activation") is not False: raise ContractError("A9_ACTIVATION")

def validate_pg04_partition(o):
    if o.get("schema_version")!="PROGRAMMING_SOLUTION_PARTITION_CONTRACT_V1" or o.get("unit")!="PG-04": raise ContractError("PG04_IDENTITY")
    if o.get("input_contract")!="ANALYSIS_IMPLEMENTATION_PACKAGE_V1" or o.get("output_contract")!="PROGRAMMING_SOLUTION_PARTITION_SET_V1": raise ContractError("PG04_BOUNDARY")
    p=o.get("partition_policy",{})
    if p.get("canonical_spec_count")!=1 or p.get("partition_unit")!="SOLUTION" or p.get("minimum_rule")!="SMALLEST_COHERENT_VALID_CHANGE": raise ContractError("PG04_PARTITION_IDENTITY")
    for k in ("semantic_boundary_first","dependency_closure_required","risk_boundary_considered","write_scope_boundary_considered","token_count_alone_must_not_define_partition","file_count_alone_must_not_define_partition","multiple_independent_canonical_specs_forbidden","shared_contracts_referenced_not_copied"):
        if p.get(k) is not True: raise ContractError("PG04_PARTITION_"+k)
    c=o.get("coverage",{})
    if c.get("material_requirement_coverage_required_percent")!=100 or c.get("acceptance_obligation_coverage_required_percent")!=100: raise ContractError("PG04_COVERAGE_PERCENT")
    for k in ("orphan_requirement_forbidden","duplicate_ownership_forbidden","cross_partition_dependencies_explicit","partition_strategy_ref_required"):
        if c.get(k) is not True: raise ContractError("PG04_COVERAGE_"+k)
    b=o.get("budget_feedback",{})
    if b.get("budget_capability")!="CONTEXT_BUDGET_GOVERNANCE" or b.get("pg07_is_runtime_enforcer") is not True or b.get("pg07_red_returns_to_pg04_for_repartition") is not True or b.get("overflow_repair_edge_is_not_a_plan_dependency_cycle") is not True or b.get("material_context_truncation_forbidden") is not True: raise ContractError("PG04_BUDGET_FEEDBACK")
    if o.get("runtime_activation") is not False or o.get("production_activation") is not False: raise ContractError("PG04_ACTIVATION")

def validate_pg07_context_budget(o):
    if o.get("schema_version")!="PROGRAMMING_CONTEXT_BUDGET_CONTRACT_V1" or o.get("unit")!="PG-07": raise ContractError("PG07_IDENTITY")
    c=o.get("capability",{})
    if c.get("code")!="CONTEXT_BUDGET_GOVERNANCE" or c.get("version_policy")!="CURRENT" or c.get("compiler_enforcement")!="public.fn_lf_router_preflight_v1(text)" or c.get("ledger")!="private.lf_context_budget_events_v2" or c.get("readback")!="public.v_lf_context_budget_latest_v2" or c.get("parallel_budget_engine_forbidden") is not True: raise ContractError("PG07_CAPABILITY")
    p=o.get("projection",{})
    if p.get("source")!="ANALYSIS_IMPLEMENTATION_PACKAGE_V1" or p.get("partition_source")!="PROGRAMMING_SOLUTION_PARTITION_SET_V1": raise ContractError("PG07_PROJECTION_SOURCE")
    for k in ("task_scoped_projection_required","lossy_summary_forbidden","full_spec_copy_to_every_worker_forbidden","full_repo_context_forbidden","material_context_truncation_forbidden","jit_exact_ref_fetch_allowed"):
        if p.get(k) is not True: raise ContractError("PG07_PROJECTION_"+k)
    required_refs={"solution_objective","applicable_requirement_refs","applicable_rule_refs","shared_contract_refs","dependency_refs","interface_refs","source_refs","acceptance_refs","write_scope","hard_boundaries"}
    if set(p.get("required_material_refs",[]))!=required_refs: raise ContractError("PG07_PROJECTION_REFS")
    b=o.get("budget_policy",{})
    if b.get("model_context_limit_source")!="RUNTIME_MODEL_CONTEXT_PROFILE" or b.get("hardcoded_model_token_limit_forbidden") is not True or b.get("reserve_values_source")!="MODEL_PROFILE_AND_BENCHMARK_DERIVED": raise ContractError("PG07_MODEL_BUDGET_SOURCE")
    if b.get("usable_input_budget_formula")!="MODEL_CONTEXT_LIMIT - GOVERNANCE_RESERVE - TOOL_READBACK_RESERVE - OUTPUT_RESERVE - RECOVERY_RESERVE": raise ContractError("PG07_BUDGET_FORMULA")
    if b.get("effective_limit_rule")!="MIN(CURRENT_TRANSVERSAL_HARD_LIMIT, MODEL_SAFE_USABLE_INPUT_BUDGET)" or b.get("transversal_policy_limit_must_be_current") is not True or b.get("window_saturation_forbidden") is not True: raise ContractError("PG07_EFFECTIVE_LIMIT")
    if b.get("soft_limit_status")!="YELLOW" or b.get("hard_limit_status")!="RED" or b.get("red_action")!="BLOCK_AND_RETURN_TO_PG04_REPARTITION_OR_JIT" or b.get("yellow_action")!="NO_ADDITIONAL_PREFETCH_PREFER_JIT" or b.get("green_action")!="CONTINUE": raise ContractError("PG07_BUDGET_ACTIONS")
    rec=o.get("receipt",{})
    if rec.get("schema_version")!="PROGRAMMING_CONTEXT_BUDGET_RECEIPT_V1": raise ContractError("PG07_RECEIPT_IDENTITY")
    fields={"projection_id","solution_id","projection_sha256","model_profile_ref","budget_policy_ref","estimated_tokens","soft_limit_tokens","hard_limit_tokens","model_safe_usable_input_budget","effective_limit_tokens","context_status","source_refs[]","verdict","overflow_action"}
    if set(rec.get("required_fields",[]))!=fields or set(rec.get("verdict_values",[]))!={"ACCEPT","BLOCK"}: raise ContractError("PG07_RECEIPT")
    if o.get("runtime_activation") is not False or o.get("production_activation") is not False: raise ContractError("PG07_ACTIVATION")

def validate_pg10_human(o):
    if o.get("schema_version")!="PROGRAMMING_HUMAN_DECISION_ROUTING_CONTRACT_V1" or o.get("unit")!="PG-10": raise ContractError("PG10_IDENTITY")
    required_inputs={"ANALYSIS_IMPLEMENTATION_PACKAGE_V1","DECISION_CONTEXT_ASOF@CURRENT","public.lf_decision_log","transversal.decision_log"}
    if set(o.get("input_sources",[]))!=required_inputs: raise ContractError("PG10_INPUTS")
    r=o.get("routing",{})
    for k in ("route_only_true_owner_decision","resolvable_evidence_gap_routes_to_targeted_evidence_not_human","implementation_strategy_owned_by_pg03_not_human","missing_implementation_alone_not_human","current_existing_decision_reused_before_new_question","duplicate_question_forbidden"):
        if r.get(k) is not True: raise ContractError("PG10_ROUTING_"+k)
    if r.get("owner_scope")!="SUPER_ADMIN" or r.get("packet_schema_version")!="PROGRAMMING_HUMAN_DECISION_PACKET_V1": raise ContractError("PG10_PACKET_IDENTITY")
    fields={"decision_code","scope_refs[]","question","options[]","recommendation","risk_if_deferred","authority_refs[]","evidence_refs[]","currentness_refs[]","owner_scope","resume_condition"}
    if set(r.get("required_packet_fields",[]))!=fields: raise ContractError("PG10_PACKET_FIELDS")
    res=o.get("resolution",{})
    if res.get("decision_receipt_surface")!="programacion.human_decisions" or res.get("decision_context_persistence")!="DECISION_CONTEXT_ASOF@CURRENT": raise ContractError("PG10_RESOLUTION_SURFACE")
    for k in ("resolved_decision_must_be_current_before_resume","resume_only_affected_scope","unrelated_ready_scope_may_continue"):
        if res.get(k) is not True: raise ContractError("PG10_RESOLUTION_"+k)
    if o.get("runtime_activation") is not False or o.get("production_activation") is not False: raise ContractError("PG10_ACTIVATION")

def validate_control_completeness(o):
    if o.get("schema_version")!="PROGRAMMING_AGENT_CONTROL_COMPLETENESS_MANIFEST_V1": raise ContractError("CONTROL_MANIFEST_IDENTITY")
    units=o.get("coverage_units",[])
    required_units={"A1","A2","A3","A4","A5","A6","A7","A8","A9","A9_PG01","PG-01","PG-04","PG-07","PG-10"}
    if {x.get("unit") for x in units}!=required_units: raise ContractError("CONTROL_MANIFEST_UNITS")
    for x in units:
        ref=x.get("contract_ref")
        if x.get("source_contract_required") is not True or x.get("validator_required") is not True or not isinstance(ref,str) or not (ROOT/ref).is_file(): raise ContractError("CONTROL_MANIFEST_MATERIALIZATION")
        if x.get("unit") in {"PG-07","PG-10"} and x.get("receipt_contract_required") is not True: raise ContractError("CONTROL_MANIFEST_RECEIPT")
    cf=o.get("critical_families",{})
    required_families={"AUTHORITY_VS_IMPLEMENTATION","EXISTING_DECISION_REUSE","HUMAN_DECISION_ROUTING","A9_PACKAGE_MATERIALIZATION","SOLUTION_PARTITION","CONTEXT_BUDGET","PROGRAMMING_CONFLICT_ROUTING"}
    if set(cf)!=required_families: raise ContractError("CONTROL_MANIFEST_FAMILIES")
    g=o.get("completeness_gate",{})
    for k in ("plan_only_control_is_not_implemented","every_covered_unit_must_have_source_contract","every_covered_unit_must_have_validator","runtime_or_human_action_control_requires_receipt_contract","missing_contract_or_validator_fails_closed"):
        if g.get(k) is not True: raise ContractError("CONTROL_MANIFEST_GATE_"+k)

def positive_request():
    return {"schema_version":"REQUEST_CONTEXT_V1","request_identity":{"request_ref":"chat://request/1","request_kind":"USER_REQUEST"},"objective":{"problem_statement":"The requested change needs analysis.","desired_outcome":"Produce a source-bound implementation analysis."},"target_hints":["repo://example"],"source_refs":["source://request/1"],"provided_facts":[{"fact_code":"F1","value":"known","source_ref":"source://request/1"}],"constraints":["NO_PRODUCTION_ACTIVATION"],"ambiguities":[{"code":"A1","statement":"Exact implementation target is not yet authoritative.","materiality":"UNKNOWN","resolution_state":"OPEN"}],"no_solution_inferred":True}

def expect_error(fn,obj,code):
    try: fn(obj)
    except ContractError as e: assert str(e)==code,(str(e),code)
    else: raise AssertionError("Expected "+code)

def self_test():
    schema=load("analysis_request_context_v1.schema.json")
    p=load("programming_entry_contract_v1.json")
    mfc=load("analysis_material_front_coverage_contract_v1.json")
    a5=load("analysis_decision_context_adr_contract_v1.json")
    stop=load("analysis_stop_rule_contract_v1.json")
    impl=load("analysis_implementability_contract_v1.json")
    parity=load("analysis_programming_handoff_parity_contract_v1.json")
    ta=load("testing_admission_contract_v1.json")
    a2=load("analysis_change_classification_contract_v1.json")
    a3=load("analysis_targeted_evidence_contract_v1.json")
    impact=load("shared_change_impact_contract_v1.json")
    tp=load("testing_wave1_design_pipeline_contract_v1.json")
    m=load("manifest_v1.json")
    a9pkg=load("analysis_implementation_package_contract_v1.json")
    pg04=load("programming_solution_partition_contract_v1.json")
    pg07=load("programming_context_budget_contract_v1.json")
    pg10=load("programming_human_decision_routing_contract_v1.json")
    cm=load("programming_agent_control_completeness_manifest_v1.json")
    assert schema["properties"]["no_solution_inferred"]["const"] is True
    assert {"story_code","agent_task_id","functional_version_id","proposed_solution"}.isdisjoint(schema["properties"])
    validate_programming_entry(p); validate_analysis_decision_context(a5); validate_material_front_coverage(mfc); validate_analysis_stop_rule(stop); validate_analysis_implementability(impl); validate_handoff_parity(parity); validate_testing_admission(ta)
    validate_analysis_change_classification(a2); validate_analysis_targeted_evidence(a3)
    validate_shared_impact(impact); validate_testing_pipeline(tp); validate_manifest(m)
    validate_analysis_package(a9pkg); validate_pg04_partition(pg04); validate_pg07_context_budget(pg07); validate_pg10_human(pg10); validate_control_completeness(cm)
    validate_request_context(positive_request())

    x=positive_request(); x["story_code"]="LEGACY-STORY"; expect_error(validate_request_context,x,"REQUEST_CONTEXT_KEYS_MISMATCH")
    x=positive_request(); x["no_solution_inferred"]=False; expect_error(validate_request_context,x,"REQUEST_CONTEXT_SOLUTION_INFERENCE")
    x=json.loads(json.dumps(p)); x["admission"]["story_identity_required"]=True; expect_error(validate_programming_entry,x,"PROGRAMMING_ADMISSION_story_identity_required")
    x=json.loads(json.dumps(p)); x["admission"]["allowed_analysis_verdicts"]=["READY"]; expect_error(validate_programming_entry,x,"PROGRAMMING_ADMISSION_VERDICTS")
    x=json.loads(json.dumps(ta)); x["modes"]["DESIGN_ONLY"]["requires"].append("frozen_candidate_ref"); expect_error(validate_testing_admission,x,"DESIGN_MODE_CANDIDATE_REQUIRED")
    x=json.loads(json.dumps(ta)); x["modes"]["EXECUTION"]["agent_task_required"]=True; expect_error(validate_testing_admission,x,"TESTING_STAGE_COUPLING")
    x=json.loads(json.dumps(a2)); x["specialist_resolution"]["hardcoded_specialist_identity_forbidden"]=False; expect_error(validate_analysis_change_classification,x,"A2_SPECIALIST_hardcoded_specialist_identity_forbidden")
    x=json.loads(json.dumps(a2)); x["specialist_resolution"]["selection_is_execution_permission"]=True; expect_error(validate_analysis_change_classification,x,"A2_SPECIALIST_selection_is_execution_permission")
    x=json.loads(json.dumps(a2)); x["classification"]["target_granularity_required"]=False; expect_error(validate_analysis_change_classification,x,"A2_TARGET_GRANULARITY")
    x=json.loads(json.dumps(a2)); x["classification"]["implementation_state_inference_forbidden"]=False; expect_error(validate_analysis_change_classification,x,"A2_IMPLEMENTATION_STATE_INFERENCE")
    x=json.loads(json.dumps(a2)); x["classification"]["depth_policy"]["arbitrary_weights_forbidden"]=False; expect_error(validate_analysis_change_classification,x,"A2_DEPTH_POLICY_NO_OVERFIT")
    x=json.loads(json.dumps(a2)); x["classification"]["depth_policy"]["unknown_material_never_L1"]=False; expect_error(validate_analysis_change_classification,x,"A2_DEPTH_POLICY_MONOTONIC")
    depth_base={"materiality_level":"LOW","scope_bounded":"TRUE","authority_state":"SUFFICIENT","reversibility_state":"DEMONSTRATED","currentness_decision":"CURRENT","material_contradiction":False,"known_cross_scope_impact":False,"unresolved_material_signal_count":0,"required_specialist_count":0}
    assert classify_analysis_depth_v1(depth_base)=="L1"
    for patch in (
        {"materiality_level":"MEDIUM"},
        {"materiality_level":"UNKNOWN"},
        {"scope_bounded":"UNKNOWN"},
        {"authority_state":"UNKNOWN"},
        {"reversibility_state":"NOT_DEMONSTRATED"},
        {"reversibility_state":"UNKNOWN"},
        {"currentness_decision":"CURRENT_REBOUND"},
        {"currentness_decision":"UNKNOWN_FAIL_CLOSED"},
        {"currentness_decision":"UNRESOLVED"},
        {"known_cross_scope_impact":"UNKNOWN"},
        {"unresolved_material_signal_count":1},
        {"required_specialist_count":1},
    ):
        q=dict(depth_base); q.update(patch); assert classify_analysis_depth_v1(q)=="L2",(patch,q)
    for patch in (
        {"materiality_level":"HIGH"},
        {"scope_bounded":"FALSE"},
        {"authority_state":"INSUFFICIENT"},
        {"currentness_decision":"STALE_AFFECTED"},
        {"material_contradiction":True},
        {"known_cross_scope_impact":True},
    ):
        q=dict(depth_base); q.update(patch); assert classify_analysis_depth_v1(q)=="L3",(patch,q)
    q=dict(depth_base); q.update({"materiality_level":"UNKNOWN","material_contradiction":True}); assert classify_analysis_depth_v1(q)=="L3"
    x=json.loads(json.dumps(a3)); x["acquisition"]["full_repository_search_without_trigger_forbidden"]=False; expect_error(validate_analysis_targeted_evidence,x,"A3_ACQUISITION_full_repository_search_without_trigger_forbidden")
    x=json.loads(json.dumps(a3)); x["target_resolution"]["authority_state_does_not_imply_implementation_state"]=False; expect_error(validate_analysis_targeted_evidence,x,"A3_STATE_INDEPENDENCE")
    x=json.loads(json.dumps(a3)); x["target_resolution"]["implementation_existing_delta_required_downstream"]=False; expect_error(validate_analysis_targeted_evidence,x,"A3_BROWNFIELD_IMPLEMENTATION")
    x=json.loads(json.dumps(a3)); x["target_resolution"]["implementation_new_requires"].remove("negative_current_implementation_evidence[]"); expect_error(validate_analysis_targeted_evidence,x,"A3_IMPLEMENTATION_NEW")
    x=json.loads(json.dumps(a3)); x["design_authority_evidence"]["resolved_literal_must_not_replace_canonical_ref"]=False; expect_error(validate_analysis_targeted_evidence,x,"A3_DESIGN_AUTHORITY")
    x=json.loads(json.dumps(p)); x["admission"]["implementation_existing_delta_required"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_ADMISSION_implementation_existing_delta_required")
    x=json.loads(json.dumps(p)); x["target_binding"]["state_dimensions_independent"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_STATE_DIMENSIONS")
    x=json.loads(json.dumps(p)); x["target_binding"]["design_literal_is_not_authority"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_DESIGN_BINDING")
    x=json.loads(json.dumps(p)); x["admission"]["programming_context_snapshot_required"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_ADMISSION_programming_context_snapshot_required")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["rediscovery_without_trigger_forbidden"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_CONTEXT_REDISCOVERY")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["transport_policy"]["large_identified"]="INLINE_FULL_PAYLOAD"; expect_error(validate_programming_entry,x,"PROGRAMMING_CONTEXT_TRANSPORT")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["allowed_requery_triggers"].append("CURIOSITY"); expect_error(validate_programming_entry,x,"PROGRAMMING_CONTEXT_REQUERY_TRIGGERS")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["technical_strategy_fields_forbidden"]=[]; expect_error(validate_programming_entry,x,"PROGRAMMING_CONTEXT_STRATEGY_LEAK")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["scope_readiness_contract"]["ready_requires_dependency_closure"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_SCOPE_READINESS_GUARDS")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["package_readiness_contract"]["partial_ready_requires_independent_execution_boundary"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_PARTIAL_READY_GUARDS")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["required_fields"].remove("scope_readiness[]"); expect_error(validate_programming_entry,x,"PROGRAMMING_CONTEXT_SNAPSHOT_FIELDS")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["required_fields"].remove("scope_front_matrix[]"); expect_error(validate_programming_entry,x,"PROGRAMMING_CONTEXT_SNAPSHOT_FIELDS")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["scope_readiness_contract"]["required_fields"].remove("material_front_refs[]"); expect_error(validate_programming_entry,x,"PROGRAMMING_SCOPE_READINESS_FIELDS")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["scope_front_consistency_contract"]["bidirectional_scope_front_mapping_required"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_SCOPE_FRONT_GUARD_bidirectional_scope_front_mapping_required")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["scope_front_consistency_contract"]["ready_scope_forbids_blocking_front"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_SCOPE_FRONT_GUARD_ready_scope_forbids_blocking_front")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["scope_front_consistency_contract"]["partial_ready_requires_every_ready_scope_front_clean"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_SCOPE_FRONT_GUARD_partial_ready_requires_every_ready_scope_front_clean")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["scope_front_consistency_contract"]["pg01_admission_requires_front_clean_ready_scope"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_SCOPE_FRONT_GUARD_pg01_admission_requires_front_clean_ready_scope")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["snapshot_currentness_contract"]["authority_capability"]="PARALLEL_CURRENTNESS"; expect_error(validate_programming_entry,x,"PROGRAMMING_SNAPSHOT_CURRENTNESS_AUTHORITY")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["snapshot_currentness_contract"]["global_main_sha_change_alone_causes_stale"]=True; expect_error(validate_programming_entry,x,"PROGRAMMING_SNAPSHOT_CURRENTNESS_MAIN_SHA")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["snapshot_currentness_contract"]["mid_execution_rebind_forbidden"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_SNAPSHOT_CURRENTNESS_mid_execution_rebind_forbidden")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["snapshot_currentness_contract"]["authority_fingerprint_change_requires_rebuild"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_SNAPSHOT_CURRENTNESS_authority_fingerprint_change_requires_rebuild")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["snapshot_currentness_contract"]["unknown_state_fail_closed"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_SNAPSHOT_CURRENTNESS_unknown_state_fail_closed")
    x=json.loads(json.dumps(p)); x["admission"]["programming_context_snapshot_receipt_required"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_ADMISSION_programming_context_snapshot_receipt_required")
    x=json.loads(json.dumps(p)); x["admission"]["material_front_coverage_required"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_ADMISSION_material_front_coverage_required")
    x=json.loads(json.dumps(p)); x["admission"]["analysis_stop_rule_required"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_ADMISSION_analysis_stop_rule_required")
    x=json.loads(json.dumps(p)); x["admission"]["implementability_schema_required"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_ADMISSION_implementability_schema_required")
    x=json.loads(json.dumps(p)); x["admission"]["handoff_parity_receipt_required"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_ADMISSION_handoff_parity_receipt_required")
    x=json.loads(json.dumps(p)); x["admission"]["snapshot_currentness_decision_required"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_ADMISSION_snapshot_currentness_decision_required")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["persistence"]["memory_only_snapshot_forbidden"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_CONTEXT_PERSISTENCE_memory_only_snapshot_forbidden")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["persistence"]["capability"]="PARALLEL_CONTEXT_STORE"; expect_error(validate_programming_entry,x,"PROGRAMMING_CONTEXT_PERSISTENCE_capability")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["persistence"]["required_receipt_fields"].remove("context_sha256"); expect_error(validate_programming_entry,x,"PROGRAMMING_CONTEXT_PERSISTENCE_RECEIPT_FIELDS")
    x=json.loads(json.dumps(a5)); x["adr_policy"]["existing_adr"]["required_state"]="CANDIDATE"; expect_error(validate_analysis_decision_context,x,"A5_ADR_CURRENT_AUTHORITY")
    x=json.loads(json.dumps(a5)); x["adr_policy"]["new_adr_required"]["a5_may_not_self_approve_new_adr"]=False; expect_error(validate_analysis_decision_context,x,"A5_NEW_ADR_BOUNDARY")
    x=json.loads(json.dumps(a5)); x["persistence"]["capability"]="PARALLEL_DECISION_CONTEXT"; expect_error(validate_analysis_decision_context,x,"A5_PERSISTENCE_capability")
    x=json.loads(json.dumps(a5)); x["decision_context"]["technical_implementation_strategy_forbidden"]=False; expect_error(validate_analysis_decision_context,x,"A5_DECISION_GUARD_technical_implementation_strategy_forbidden")
    x=json.loads(json.dumps(a5)); x["scope_readiness_boundary"]["unrelated_independent_ready_scope_may_proceed"]=False; expect_error(validate_analysis_decision_context,x,"A5_SCOPE_unrelated_independent_ready_scope_may_proceed")
    x=json.loads(json.dumps(a5)); x["integration_boundary"]["a9_must_preserve_full_artifact"]=False; expect_error(validate_analysis_decision_context,x,"A5_INTEGRATION")
    x=json.loads(json.dumps(p)); x["admission"]["decision_context_required"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_ADMISSION_decision_context_required")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["required_fields"].remove("decision_context"); expect_error(validate_programming_entry,x,"PROGRAMMING_CONTEXT_SNAPSHOT_FIELDS")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["decision_context"]["technical_strategy_owned_by"]="ANALYSIS"; expect_error(validate_programming_entry,x,"PROGRAMMING_DECISION_CONTEXT_STRATEGY_BOUNDARY")
    x=json.loads(json.dumps(mfc)); x["front_discovery"]["front_kind_policy"]="STATIC_CLOSED_CATALOG"; expect_error(validate_material_front_coverage,x,"MFC_OPEN_CATALOG")
    x=json.loads(json.dumps(mfc)); x["coverage_guards"]["silent_omission_forbidden"]=False; expect_error(validate_material_front_coverage,x,"MFC_GUARD_silent_omission_forbidden")
    x=json.loads(json.dumps(mfc)); x["coverage_guards"]["not_applicable_requires_evidence_and_reason"]=False; expect_error(validate_material_front_coverage,x,"MFC_GUARD_not_applicable_requires_evidence_and_reason")
    x=json.loads(json.dumps(mfc)); x["coverage_guards"]["reuse_as_is_requires_currentness"]=False; expect_error(validate_material_front_coverage,x,"MFC_GUARD_reuse_as_is_requires_currentness")
    x=json.loads(json.dumps(mfc)); x["integration_boundary"]["no_stop_rule_change_in_this_contract"]=False; expect_error(validate_material_front_coverage,x,"MFC_MICROLOT_BOUNDARY")
    x=json.loads(json.dumps(stop)); x["decision"]["stop_requires"].remove("all_material_fronts_accounted=true"); expect_error(validate_analysis_stop_rule,x,"STOP_RULE_REQUIREMENTS")
    x=json.loads(json.dumps(stop)); x["decision"]["stable_decision_with_incomplete_front_coverage_forbids_stop"]=False; expect_error(validate_analysis_stop_rule,x,"STOP_RULE_FAIL_CLOSED")
    x=json.loads(json.dumps(stop)); x["continuation_policy"]["no_curiosity_search"]=False; expect_error(validate_analysis_stop_rule,x,"STOP_RULE_CONTINUATION")
    x=json.loads(json.dumps(stop)); x["integration_boundary"]["scope_readiness_policy_unchanged_in_this_microlot"]=False; expect_error(validate_analysis_stop_rule,x,"STOP_RULE_MICROLOT_BOUNDARY")
    x=json.loads(json.dumps(impl)); x["requirement_contract"]["obligation_modes"].remove("MUST_PRESERVE_EXACT"); expect_error(validate_analysis_implementability,x,"IMPLEMENTABILITY_OBLIGATION_MODES")
    x=json.loads(json.dumps(impl)); x["requirement_contract"]["required_fields"].remove("permission_refs[]"); expect_error(validate_analysis_implementability,x,"IMPLEMENTABILITY_REQUIREMENT_FIELDS")
    x=json.loads(json.dumps(impl)); x["binding_contract"]["binding_kind_policy"]="STATIC_CLOSED_CATALOG"; expect_error(validate_analysis_implementability,x,"IMPLEMENTABILITY_BINDING_KIND_POLICY")
    x=json.loads(json.dumps(impl)); x["binding_contract"]["resolved_literal_may_not_replace_canonical_ref"]=False; expect_error(validate_analysis_implementability,x,"IMPLEMENTABILITY_BINDING_AUTHORITY")
    x=json.loads(json.dumps(impl)); x["completeness_guards"]["material_permission_unknown_requires_blocker"]=False; expect_error(validate_analysis_implementability,x,"IMPLEMENTABILITY_GUARD_material_permission_unknown_requires_blocker")
    x=json.loads(json.dumps(impl)); x["strategy_boundary"]["forbidden_fields"]=[]; expect_error(validate_analysis_implementability,x,"IMPLEMENTABILITY_STRATEGY_BOUNDARY")
    x=json.loads(json.dumps(parity)); x["shared_snapshot_contract"]["shared_schema_digest_required"]=False; expect_error(validate_handoff_parity,x,"HANDOFF_PARITY_SHARED_SCHEMA_GUARDS")
    x=json.loads(json.dumps(parity)); x["shared_snapshot_contract"]["parallel_receiver_schema_forbidden"]=False; expect_error(validate_handoff_parity,x,"HANDOFF_PARITY_SHARED_SCHEMA_GUARDS")
    x=json.loads(json.dumps(parity)); x["receiver_requirements"]["context_sha256_must_match_receipt"]=False; expect_error(validate_handoff_parity,x,"HANDOFF_PARITY_RECEIVER")
    x=json.loads(json.dumps(parity)); x["receiver_requirements"]["receiver_schema_digest_must_match_producer_schema_digest"]=False; expect_error(validate_handoff_parity,x,"HANDOFF_PARITY_RECEIVER")
    x=json.loads(json.dumps(parity)); x["receiver_requirements"]["lossy_material_projection_forbidden"]=False; expect_error(validate_handoff_parity,x,"HANDOFF_PARITY_RECEIVER_FAIL_CLOSED")
    x=json.loads(json.dumps(parity)); x["receipt"]["required_fields"].remove("material_projection_sha256"); expect_error(validate_handoff_parity,x,"HANDOFF_PARITY_RECEIPT")
    x=json.loads(json.dumps(p)); x["target_binding"]["implementation_strategy_owned_by"]="ANALYSIS"; expect_error(validate_programming_entry,x,"PROGRAMMING_STRATEGY_OWNER")
    x=json.loads(json.dumps(impact)); x["testing_projection"]["consumes_same_core"]=False; expect_error(validate_shared_impact,x,"IMPACT_TESTING_REUSE")
    x=json.loads(json.dumps(tp)); x["story_required"]=True; expect_error(validate_testing_pipeline,x,"TEST_PIPELINE_STAGE_COUPLING")
    x=json.loads(json.dumps(m)); x["contracts"]["TST-05"]="testing_private_impact_engine.json"; expect_error(validate_manifest,x,"MANIFEST_SHARED_IMPACT_SPLIT")
    x=json.loads(json.dumps(a5)); x["existing_decision_resolution"]["current_existing_decision_must_be_reused"]=False; expect_error(validate_analysis_decision_context,x,"A5_EXISTING_DECISION_current_existing_decision_must_be_reused")
    x=json.loads(json.dumps(a5)); x["human_decision_routing"]["missing_implementation_alone_must_not_be_routed_to_human"]=False; expect_error(validate_analysis_decision_context,x,"A5_HUMAN_ROUTING_missing_implementation_alone_must_not_be_routed_to_human")
    x=json.loads(json.dumps(a5)); x["human_decision_routing"]["pending_packet_must_be_exposed_in_a9_output"]=False; expect_error(validate_analysis_decision_context,x,"A5_HUMAN_ROUTING_pending_packet_must_be_exposed_in_a9_output")
    x=json.loads(json.dumps(mfc)); x["blocker_semantics"]["implementation_absence_alone_is_not_analysis_blocker"]=False; expect_error(validate_material_front_coverage,x,"MFC_BLOCKER_SEMANTICS_implementation_absence_alone_is_not_analysis_blocker")
    x=json.loads(json.dumps(mfc)); x["blocker_semantics"]["blocked_front_requires_one_of"].append("IMPLEMENTATION_MISSING"); expect_error(validate_material_front_coverage,x,"MFC_BLOCKER_SEMANTICS_ALLOWED")
    x=json.loads(json.dumps(stop)); x["human_decision_routing_guard"]["requires_decision_before_stop_must_have_human_packet"]=False; expect_error(validate_analysis_stop_rule,x,"STOP_RULE_HUMAN_ROUTING_requires_decision_before_stop_must_have_human_packet")
    x=json.loads(json.dumps(a9pkg)); x["assembly_policy"]["single_canonical_spec"]=False; expect_error(validate_analysis_package,x,"A9_PACKAGE_ASSEMBLY_single_canonical_spec")
    x=json.loads(json.dumps(a9pkg)); x["decision_visibility"]["generic_blocker_only_representation_forbidden"]=False; expect_error(validate_analysis_package,x,"A9_HUMAN_DECISION_generic_blocker_only_representation_forbidden")
    x=json.loads(json.dumps(a9pkg)); x["qualification"]["missing_implementation_alone_must_not_force_blocked"]=False; expect_error(validate_analysis_package,x,"A9_PACKAGE_QUALIFICATION_missing_implementation_alone_must_not_force_blocked")
    x=json.loads(json.dumps(pg04)); x["partition_policy"]["token_count_alone_must_not_define_partition"]=False; expect_error(validate_pg04_partition,x,"PG04_PARTITION_token_count_alone_must_not_define_partition")
    x=json.loads(json.dumps(pg04)); x["partition_policy"]["canonical_spec_count"]=2; expect_error(validate_pg04_partition,x,"PG04_PARTITION_IDENTITY")
    x=json.loads(json.dumps(pg04)); x["coverage"]["material_requirement_coverage_required_percent"]=99; expect_error(validate_pg04_partition,x,"PG04_COVERAGE_PERCENT")
    x=json.loads(json.dumps(pg07)); x["capability"]["code"]="PARALLEL_CONTEXT_BUDGET"; expect_error(validate_pg07_context_budget,x,"PG07_CAPABILITY")
    x=json.loads(json.dumps(pg07)); x["budget_policy"]["hardcoded_model_token_limit_forbidden"]=False; expect_error(validate_pg07_context_budget,x,"PG07_MODEL_BUDGET_SOURCE")
    x=json.loads(json.dumps(pg07)); x["projection"]["material_context_truncation_forbidden"]=False; expect_error(validate_pg07_context_budget,x,"PG07_PROJECTION_material_context_truncation_forbidden")
    x=json.loads(json.dumps(pg07)); x["receipt"]["required_fields"].remove("estimated_tokens"); expect_error(validate_pg07_context_budget,x,"PG07_RECEIPT")
    x=json.loads(json.dumps(pg10)); x["routing"]["current_existing_decision_reused_before_new_question"]=False; expect_error(validate_pg10_human,x,"PG10_ROUTING_current_existing_decision_reused_before_new_question")
    x=json.loads(json.dumps(pg10)); x["routing"]["missing_implementation_alone_not_human"]=False; expect_error(validate_pg10_human,x,"PG10_ROUTING_missing_implementation_alone_not_human")
    x=json.loads(json.dumps(cm)); x["coverage_units"]=[u for u in x["coverage_units"] if u["unit"]!="PG-07"]; expect_error(validate_control_completeness,x,"CONTROL_MANIFEST_UNITS")
    x=json.loads(json.dumps(cm)); [u for u in x["coverage_units"] if u["unit"]=="PG-10"][0]["receipt_contract_required"]=False; expect_error(validate_control_completeness,x,"CONTROL_MANIFEST_RECEIPT")
    x=json.loads(json.dumps(p)); x["downstream_control_bindings"]["context_budget_owner"]="PG-01"; expect_error(validate_programming_entry,x,"PROGRAMMING_DOWNSTREAM_CONTROL_context_budget_owner")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["material_front_coverage"]["implementation_absence_alone_must_not_block"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_IMPLEMENTATION_ABSENCE_FALSE_BLOCKER")
    x=json.loads(json.dumps(p)); x["programming_context_snapshot"]["decision_context"]["pending_human_decision_packets_must_be_preserved"]=False; expect_error(validate_programming_entry,x,"PROGRAMMING_DECISION_CONTEXT_HUMAN_ROUTING")
    print("PASS_WAVE1_BOUNDARY_CONTRACTS target_state_split=PASS design_binding=PASS context_snapshot=PASS material_front_coverage=PASS stop_rule=PASS implementability_schema=PASS handoff_parity=PASS scope_front_consistency=PASS snapshot_currentness=PASS scope_readiness=PASS snapshot_persistence=PASS human_decision_routing=PASS implementation_absence_semantics=PASS a9_package=PASS solution_partition=PASS context_budget=PASS control_completeness=PASS negatives=122")

if __name__=="__main__":
    if "--self-test" not in sys.argv: raise SystemExit("usage: validate_wave1_boundary_contracts_v1.py --self-test")
    self_test()
