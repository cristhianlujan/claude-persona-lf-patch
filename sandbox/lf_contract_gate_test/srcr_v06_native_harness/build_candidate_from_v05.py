#!/usr/bin/env python3
"""Build the SRCR V0.6 Lifecycle candidate from the exact frozen V0.5 bytes.

Sandbox-only deterministic transform. This does not inspect the oracle, call a
model, mutate Supabase, activate runtime, merge, publish, or touch production.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path

from profiles.systemic_root_cause_repair_lf.validators.closure_proof import (
    canonical_evidence_bundle_digest,
)

V06 = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6"


def proof(status: str, refs=None, applicability: str = "REQUIRED"):
    refs = list(refs or [])
    return {
        "applicability": applicability,
        "status": status,
        "evidence_refs": refs,
    }


def edge(
    edge_id,
    from_node,
    to_node,
    edge_kind,
    observation_status,
    proposed_change_ref,
    gap_refs,
    *,
    producer_refs=None,
    transport_refs=None,
    consumer_refs=None,
    enforcement_refs=None,
    readback_refs=None,
    next_gate=None,
    next_refs=None,
    proposed_next_consumer=None,
    route=None,
    currentness=None,
    terminality=None,
    identity=None,
    rollback=None,
):
    return {
        "edge_id": edge_id,
        "from_node": from_node,
        "to_node": to_node,
        "edge_kind": edge_kind,
        "observation_status": observation_status,
        "disposition": "IMPLEMENTABLE",
        "producer_evidence_refs": list(producer_refs or []),
        "transport_evidence_refs": list(transport_refs or []),
        "consumer_evidence_refs": list(consumer_refs or []),
        "enforcement_evidence_refs": list(enforcement_refs or []),
        "effect_readback_evidence_refs": list(readback_refs or []),
        "gap_evidence_refs": list(gap_refs or []),
        "next_gate": next_gate,
        "next_gate_consumer_evidence_refs": list(next_refs or []),
        "proposed_next_gate_consumer_ref": proposed_next_consumer,
        "canonical_route_consistency": route or proof("PROPOSED_ONLY"),
        "post_transition_currentness": currentness or proof("PROPOSED_ONLY"),
        "terminality": terminality or proof("PROPOSED_ONLY"),
        "identity_consistency": identity or proof("PROPOSED_ONLY"),
        "rollback_executability": rollback or proof("PROPOSED_ONLY"),
        "proposed_change_ref": proposed_change_ref,
        "blocking_uncertainty_id": None,
    }


def add_unique(rows, key, row):
    value = row[key]
    if not any(isinstance(x, dict) and x.get(key) == value for x in rows):
        rows.append(row)


def build_candidate(base):
    c = copy.deepcopy(base)
    c["profile_pack_id"] = V06

    # Generic schema-aware producer correction found by the frozen V0.5 run.
    for reg in c.get("planned_regressions", []):
        tp = reg.get("test_protocol") if isinstance(reg, dict) else None
        if not isinstance(tp, dict):
            continue
        for k in ("setup", "action"):
            if isinstance(tp.get(k), str):
                tp[k] = [tp[k]]

    delta = c.setdefault("implementation_delta", [])
    add_unique(delta, "target", {
        "target": "supabase://proposed/PROFILE_RELEASE_CONTRACT_V1",
        "action": "create the immutable release contract and all selected materialization, runtime-binding and post-refresh reconciliation edges",
        "rationale": "Multiple implementable lifecycle edges share one release authority and must be declared as one bounded artifact family rather than graph-only changes.",
        "evidence_refs": ["EV-LC-004", "EV-LC-006", "EV-LC-015", "EV-LC-025"],
    })
    add_unique(delta, "target", {
        "target": "supabase://proposed/PROFILE_RELEASE_QUALIFICATION_BINDING_V1",
        "action": "bind release materialization to the existing qualification lifecycle before promotion",
        "rationale": "The materialize-to-qualify edge is part of the selected repair and must be present in the declared implementation footprint.",
        "evidence_refs": ["EV-LC-006", "EV-LC-036"],
    })
    add_unique(delta, "target", {
        "target": "supabase://proposed/PROFILE_RELEASE_ACCEPTANCE_LAYERS_V1",
        "action": "enforce distinct deterministic, independent semantic, canonical quality and operational authorization layers",
        "rationale": "Qualification-to-promotion and verify-to-execute edges both depend on this selected authority boundary.",
        "evidence_refs": ["EV-LC-028", "EV-LC-029", "EV-LC-035", "EV-LC-036"],
    })
    add_unique(delta, "target", {
        "target": "supabase://proposed/PROFILE_RELEASE_TRANSITION_POLICY_V1",
        "action": "define governed promote, deprecate, rollback and rollback-refresh transitions for exact release identities",
        "rationale": "Every selected lifecycle state-transition edge must reconcile to a declared implementation target.",
        "evidence_refs": ["EV-LC-006", "EV-LC-011", "EV-LC-021"],
    })
    add_unique(delta, "target", {
        "target": "supabase://proposed/PROFILE_RELEASE_COMPATIBILITY_WINDOW_V1",
        "action": "enforce no-new-adoption and active-consumer drain before retirement",
        "rationale": "The deprecate-to-retire edge is selected and requires an explicit declared compatibility/retirement artifact.",
        "evidence_refs": ["EV-LC-005", "EV-LC-021"],
    })
    add_unique(delta, "target", {
        "target": "supabase://proposed/GESTION_RELEASE_PERFIL_LF/runtime_canary_consumer",
        "action": "bind PROFILE_RUNTIME_CANARY_REQUIRED to a governed verify-runtime-canary consumer",
        "rationale": "The current refresh path emits a canary-required gate without an operational consumer; the selected repair must name and wire the future consumer.",
        "evidence_refs": ["EV-LC-018", "EV-LC-025"],
    })
    add_unique(delta, "target", {
        "target": "supabase://proposed/EJECUCION_PERFIL_LF/queue_terminal_bridge",
        "action": "reconcile terminal queue outcomes into the canonical execution state",
        "rationale": "A failed runtime queue request can remain disconnected from the canonical execution terminal state; the selected repair requires deterministic propagation and readback.",
        "evidence_refs": ["EV-LC-019", "EV-LC-020", "EV-LC-023"],
    })

    pkg = c.get("implementation_package")
    if not isinstance(pkg, dict):
        raise RuntimeError("IMPLEMENTATION_PACKAGE_REQUIRED")

    ads = pkg.setdefault("architecture_decisions", [])
    if ads:
        ad1 = ads[0]
        if isinstance(ad1, dict) and ad1.get("alternatives_considered") == ["A", "B", "C"]:
            ad1["alternatives_considered"] = [
                "Git-only lifecycle authority",
                "Supabase-governed thin release boundary",
                "Monolithic runtime lifecycle engine",
            ]

    add_unique(ads, "decision_id", {
        "decision_id": "AD-4",
        "question": "How are quality acceptance and operational promotion separated?",
        "decision": (
            "Use three explicit non-substitutable layers: deterministic structural floor, "
            "independent semantic acceptance with canonical quality receipt, and a separate "
            "operational authorization/promotion transition. No earlier layer self-authorizes the next."
        ),
        "authority_ref": "proposed://PROFILE_RELEASE_ACCEPTANCE_LAYERS_V1",
        "rationale": (
            "Observed runtime paths declare quality controls but do not consume them into a true "
            "downstream authorization path; separating the layers prevents validator PASS from "
            "becoming implicit promotion."
        ),
        "alternatives_considered": [
            "Treat deterministic validation as sufficient acceptance",
            "Treat semantic acceptance as automatic operational promotion",
            "Keep deterministic, semantic, and operational authorization as distinct gates",
        ],
        "evidence_refs": [
            "github://services/profile_runtime_api/profile_runtime_api/validation.py",
            "github://services/profile_runtime_api/profile_runtime_api/engine.py",
            "supabase://public/lf_operation_step_judge_bindings",
        ],
    })
    add_unique(ads, "decision_id", {
        "decision_id": "AD-5",
        "question": "How do remaining consumers migrate during deprecation?",
        "decision": (
            "Deprecation immediately blocks new adoption, while existing consumers remain explicitly "
            "inventoried and supported in a drain stage. Retirement is enabled only after the "
            "authoritative active-consumer inventory reaches zero and terminal archive/readback passes."
        ),
        "authority_ref": "proposed://PROFILE_RELEASE_COMPATIBILITY_WINDOW_V1",
        "rationale": (
            "This creates a bounded state transition without inventing a calendar deadline; the exit "
            "condition is measurable consumer state rather than elapsed time."
        ),
        "alternatives_considered": [
            "Immediate retirement at deprecation",
            "Fixed calendar grace period without authority",
            "Consumer-inventory drain stage with zero-consumer exit",
        ],
        "evidence_refs": [
            "supabase://public/lf_operation_registry/RETIRO_ACTIVO_LF",
            "supabase://public/lf_router_action_registry?asset_type=PERFIL",
        ],
    })

    controls = pkg.setdefault("control_matrix", [])
    add_unique(controls, "control_id", {
        "control_id": "CTL-QUALITY-AUTH",
        "purpose": "Prevent structural or semantic PASS from implicitly authorizing promotion.",
        "authority_ref": "proposed://PROFILE_RELEASE_ACCEPTANCE_LAYERS_V1",
        "applies_when": "A release requests promotion or downstream authorization.",
        "enforcement_point_ref": "proposed://GESTION_RELEASE_PERFIL_LF/promote",
        "input_contract": (
            "Structural floor PASS + independent semantic PASS + canonical quality receipt + "
            "separate operational authorization bound to the exact release identity."
        ),
        "blocking_code": "PROFILE_RELEASE_QUALITY_OR_AUTHORIZATION_INCOMPLETE",
        "observable_result": "Desired binding and downstream authorization remain unchanged.",
        "verification_method": "Negative matrix removes each layer independently and proves fail-closed behavior.",
    })
    add_unique(controls, "control_id", {
        "control_id": "CTL-COMPAT-DRAIN",
        "purpose": "Protect remaining consumers between deprecation and terminal retirement.",
        "authority_ref": "proposed://PROFILE_RELEASE_COMPATIBILITY_WINDOW_V1",
        "applies_when": "A release is deprecated or superseded while active consumers remain.",
        "enforcement_point_ref": "proposed://GESTION_RELEASE_PERFIL_LF/deprecate",
        "input_contract": "No-new-adoption marker + authoritative active-consumer inventory + terminal readback.",
        "blocking_code": "PROFILE_RELEASE_CONSUMER_DRAIN_INCOMPLETE",
        "observable_result": "Release remains deprecated/superseded and cannot retire while consumer count is nonzero.",
        "verification_method": "Active-consumer, zero-consumer and replay cases over the governed retirement check.",
    })

    add_unique(controls, "control_id", {
        "control_id": "CTL-RUNTIME-CANARY-CONSUMER",
        "purpose": "Guarantee that PROFILE_RUNTIME_CANARY_REQUIRED is consumed by a governed lifecycle action rather than remaining a label-only gate.",
        "authority_ref": "proposed://GESTION_RELEASE_PERFIL_LF/runtime_canary_consumer",
        "applies_when": "REFRESCO_RUNTIME has applied a desired release and post-refresh verification is required.",
        "enforcement_point_ref": "proposed://GESTION_RELEASE_PERFIL_LF/verify_runtime_canary",
        "input_contract": "Exact release identity + refresh readback + PROFILE_RUNTIME_CANARY_REQUIRED gate.",
        "blocking_code": "PROFILE_RUNTIME_CANARY_CONSUMER_MISSING",
        "observable_result": "Canary result and observed release state are recorded against the exact release before execution authorization.",
        "verification_method": "Negative no-consumer case must fail; positive consumer path must show producer, transport, consumer, enforcement and readback.",
    })
    add_unique(controls, "control_id", {
        "control_id": "CTL-QUEUE-CANONICAL-TERMINALITY",
        "purpose": "Keep runtime queue terminal outcome and canonical EJECUCION_PERFIL_LF terminal state consistent.",
        "authority_ref": "proposed://EJECUCION_PERFIL_LF/queue_terminal_bridge",
        "applies_when": "A runtime queue request reaches SUCCEEDED, FAILED or CANCELLED for a governed profile execution.",
        "enforcement_point_ref": "proposed://EJECUCION_PERFIL_LF/reconcile_queue_terminal",
        "input_contract": "Queue request identity + producer execution identity + terminal queue state + failure/success evidence.",
        "blocking_code": "PROFILE_EXECUTION_TERMINALITY_RECONCILIATION_FAILED",
        "observable_result": "Canonical execution reaches the corresponding terminal state or the reconciliation fails closed with explicit evidence.",
        "verification_method": "Inject terminal success/failure/cancelled queue outcomes and read back canonical execution state for the same identity.",
    })

    policies = pkg.setdefault("policy_contract_changes", [])
    add_unique(policies, "authority_ref", {
        "authority_ref": "proposed://PROFILE_RELEASE_ACCEPTANCE_LAYERS_V1",
        "change": (
            "Codify deterministic floor -> independent semantic acceptance -> canonical quality receipt "
            "-> operational authorization/promotion as separate, exact-identity-bound layers."
        ),
        "owner_ref": "supabase://public/lf_activos/ACT-0045",
        "compatibility_rule": (
            "Existing validators and judges remain reusable but none may self-authorize promotion or "
            "downstream execution merely by returning PASS."
        ),
        "evidence_refs": [
            "github://services/profile_runtime_api/profile_runtime_api/validation.py",
            "github://services/profile_runtime_api/profile_runtime_api/engine.py",
            "supabase://public/lf_operation_step_judge_bindings",
        ],
    })
    add_unique(policies, "authority_ref", {
        "authority_ref": "proposed://PROFILE_RELEASE_COMPATIBILITY_WINDOW_V1",
        "change": (
            "Add a deprecation drain stage: reject new adoption immediately, inventory existing consumers, "
            "maintain compatibility for them, and permit retirement only at zero active consumers with readback."
        ),
        "owner_ref": "supabase://public/lf_operation_registry/RETIRO_ACTIVO_LF",
        "compatibility_rule": (
            "No invented time window. Existing consumers keep the prior exact release during drain; "
            "new consumers must bind a non-deprecated release."
        ),
        "evidence_refs": [
            "supabase://public/lf_operation_registry/RETIRO_ACTIVO_LF",
            "supabase://public/lf_router_action_registry?asset_type=PERFIL",
        ],
    })

    wiring = pkg.setdefault("wiring", [])
    create_wire = {
        "from_ref": "CREACION_PERFIL_LF.canonical_registration_readback",
        "to_ref": "GESTION_RELEASE_PERFIL_LF.materialize",
        "contract_ref": "PROFILE_RELEASE_CONTRACT_V1",
        "data_carried": [
            "profile_code",
            "exact source revision",
            "canonical asset identity",
            "entrypoint/manifest/runtime-binding refs",
            "creation receipt",
        ],
        "precondition": "Create completed with canonical asset registration and exact readback.",
        "fail_closed_behavior": "Do not close CREATE as lifecycle-complete or create a promotable release if registration/readback is absent.",
    }
    if not any(isinstance(x, dict) and x.get("from_ref") == create_wire["from_ref"] and x.get("to_ref") == create_wire["to_ref"] for x in wiring):
        wiring.insert(0, create_wire)
    quality_wire = {
        "from_ref": "SYSTEMIC_ROOT_CAUSE_REPAIR_LF.pre_quality_floors",
        "to_ref": "independent_semantic_judge",
        "contract_ref": "PROFILE_RELEASE_ACCEPTANCE_LAYERS_V1",
        "data_carried": ["exact candidate identity", "external evidence manifest", "scope authority packet"],
        "precondition": "Output schema, runtime_validate and semantic utility all pass without quality acceptance.",
        "fail_closed_behavior": "No canonical quality receipt or operational promotion authority is created.",
    }
    if not any(isinstance(x, dict) and x.get("from_ref") == quality_wire["from_ref"] for x in wiring):
        wiring.append(quality_wire)
    auth_wire = {
        "from_ref": "canonical_quality_receipt",
        "to_ref": "GESTION_RELEASE_PERFIL_LF.promote",
        "contract_ref": "PROFILE_RELEASE_ACCEPTANCE_LAYERS_V1",
        "data_carried": ["release_id", "candidate digest", "independent verdict", "canonical quality receipt ref"],
        "precondition": "Canonical quality receipt is independently materialized for the exact current candidate/release.",
        "fail_closed_behavior": "Quality PASS alone never mutates desired binding; promotion still requires explicit operational authorization.",
    }
    if not any(isinstance(x, dict) and x.get("from_ref") == auth_wire["from_ref"] for x in wiring):
        wiring.append(auth_wire)

    canary_wire = {
        "from_ref": "REFRESCO_RUNTIME.post_refresh",
        "to_ref": "GESTION_RELEASE_PERFIL_LF.verify_runtime_canary",
        "contract_ref": "PROFILE_RUNTIME_CANARY_REQUIRED",
        "data_carried": ["release_id", "desired_release_id", "refresh readback", "runtime binding identity"],
        "precondition": "Refresh completed for the exact desired release and canary verification is required.",
        "fail_closed_behavior": "Do not mark observed release verified and do not authorize execution while the canary consumer/result is absent.",
    }
    if not any(isinstance(x, dict) and x.get("to_ref") == canary_wire["to_ref"] for x in wiring):
        wiring.append(canary_wire)

    terminal_wire = {
        "from_ref": "private.lf_profile_runtime_queue_v1.terminal_outcome",
        "to_ref": "EJECUCION_PERFIL_LF.reconcile_queue_terminal",
        "contract_ref": "PROFILE_EXECUTION_QUEUE_TERMINALITY_V1",
        "data_carried": ["queue_request_id", "producer_execution_id", "terminal_status", "error_code", "terminal evidence ref"],
        "precondition": "Queue request is terminal and is bound to one canonical profile execution identity.",
        "fail_closed_behavior": "Do not leave the canonical execution IN_PROGRESS after an authoritative terminal queue outcome; reconciliation mismatch is an explicit blocker.",
    }
    if not any(isinstance(x, dict) and x.get("to_ref") == terminal_wire["to_ref"] for x in wiring):
        wiring.append(terminal_wire)

    deliverables = pkg.setdefault("deliverables", [])
    add_unique(deliverables, "artifact_ref", {
        "artifact_ref": "proposed://GESTION_RELEASE_PERFIL_LF/runtime_canary_consumer",
        "change_type": "BIND",
        "exact_delta": "Bind PROFILE_RUNTIME_CANARY_REQUIRED to verify_runtime_canary and persist exact-release canary/readback before execution authorization.",
        "dependencies": ["PROFILE_RELEASE_CONTRACT_V1", "REFRESCO_RUNTIME", "PROFILE_RUNTIME_CANARY_REQUIRED"],
        "acceptance_refs": ["CTL-RUNTIME-CANARY-CONSUMER", "EDGE-REFRESH-VERIFY"],
    })
    add_unique(deliverables, "artifact_ref", {
        "artifact_ref": "proposed://EJECUCION_PERFIL_LF/queue_terminal_bridge",
        "change_type": "MODIFY",
        "exact_delta": "Add idempotent terminal queue reconciliation so SUCCEEDED/FAILED/CANCELLED outcomes update or explicitly reconcile the canonical execution state with exact identity and readback.",
        "dependencies": ["private.lf_profile_runtime_queue_v1", "lf_operation_execution", "EJECUCION_PERFIL_LF"],
        "acceptance_refs": ["CTL-QUEUE-CANONICAL-TERMINALITY", "EDGE-EXECUTE-TERMINAL-READBACK"],
    })

    obs = pkg.setdefault("observability_plan", [])
    add_unique(obs, "signal", {
        "signal": "quality_acceptance_vs_operational_authorization",
        "source_ref": "proposed://PROFILE_RELEASE_ACCEPTANCE_LAYERS_V1",
        "expected_change": "Quality receipt and operational promotion receipt remain separately addressable and exact-identity-bound.",
        "alert_or_gate": "PROFILE_RELEASE_QUALITY_OR_AUTHORIZATION_INCOMPLETE",
    })
    add_unique(obs, "signal", {
        "signal": "deprecated_release_active_consumer_count",
        "source_ref": "supabase://public/lf_operation_registry/RETIRO_ACTIVO_LF",
        "expected_change": "No-new-adoption at deprecation; active consumer count monotonically drains to zero before retirement.",
        "alert_or_gate": "PROFILE_RELEASE_CONSUMER_DRAIN_INCOMPLETE",
    })

    # Transition policy: make the compatibility window a state/exit condition, not an invented duration.
    plan = c.get("transition_plan")
    if isinstance(plan, dict):
        compat = plan.get("compatibility_rule", "")
        if "drain" not in compat.lower():
            plan["compatibility_rule"] = (
                compat.rstrip(".") +
                ". Deprecation blocks new adoption immediately; existing consumers stay on their exact release "
                "during an explicit drain stage until authoritative active-consumer inventory reaches zero."
            )
        stages = plan.get("stages")
        if isinstance(stages, list):
            retire_idx = next((
                i for i, x in enumerate(stages)
                if isinstance(x, dict) and "RETIRE" in str(x.get("stage_id", "")).upper()
            ), None)
            drain = {
                "stage_id": "T4-COMPAT-DRAIN",
                "entry_condition": "Release is deprecated/superseded and no-new-adoption is enforced.",
                "changes": [
                    "Inventory every active consumer against the exact deprecated release identity.",
                    "Keep existing consumers on the exact release while preventing new bindings.",
                    "Re-read consumer inventory after migration/rebinding actions.",
                ],
                "exit_condition": "Authoritative active-consumer inventory is zero and readback is current.",
                "rollback_scope": "Cancel retirement enablement and remain deprecated/superseded; do not restore new adoption implicitly.",
            }
            if not any(isinstance(x, dict) and x.get("stage_id") == drain["stage_id"] for x in stages):
                if retire_idx is None:
                    stages.append(drain)
                else:
                    stages.insert(retire_idx, drain)
                    if isinstance(stages[retire_idx + 1], dict):
                        stages[retire_idx + 1]["stage_id"] = "T5-RETIRE-ENABLE"

    # Strengthen CREATE criterion with the missing first release edge.
    for ac in c.get("acceptance_criteria", []):
        if not isinstance(ac, dict):
            continue
        text = " ".join(str(ac.get(k, "")) for k in ("criterion", "verification_method", "expected_result")).upper()
        if "CREATE" in text:
            ac["criterion"] = (
                "CREATE closes only after canonical asset registration/readback and first immutable non-promoted release materialization."
            )
            ac["verification_method"] = (
                "Execute isolated CREATE, resolve canonical asset/source readback, materialize the first release, and verify exact identity linkage."
            )
            ac["expected_result"] = (
                "Creation cannot be lifecycle-complete while registration or first release identity is absent; no implicit promotion occurs."
            )
            break

    criteria = c.setdefault("acceptance_criteria", [])
    if not any("three acceptance" in str(x.get("criterion", "")).lower() for x in criteria if isinstance(x, dict)):
        criteria.append({
            "criterion": "The three acceptance layers remain independently observable and non-substitutable.",
            "verification_method": "Remove structural PASS, semantic PASS, quality receipt, and operational authorization one at a time.",
            "expected_result": "Each missing layer blocks only its downstream transition; no earlier PASS implies promotion.",
        })
    if not any("consumer drain" in str(x.get("criterion", "")).lower() for x in criteria if isinstance(x, dict)):
        criteria.append({
            "criterion": "Deprecated releases enforce a consumer drain window before retirement.",
            "verification_method": "Test active-consumer block, no-new-adoption, zero-consumer exit and terminal archive readback.",
            "expected_result": "Retirement remains blocked until active consumers equal zero; existing consumers are preserved during drain.",
        })

    evidence_map = c.setdefault("evidence_map", [])
    if not any(
        isinstance(row, dict) and row.get("claim_path") == "$.current_uncertainties"
        for row in evidence_map
    ):
        evidence_map.append({
            "claim_path": "$.current_uncertainties",
            "evidence_refs": [
                "supabase://public/lf_operation_registry/RETIRO_ACTIVO_LF",
                "supabase://public/lf_router_action_registry?asset_type=PERFIL",
            ],
        })

    # Explicit material-edge inventory. These are observed gaps with implementable
    # repairs or proposed internal edges; none is claimed REUSE_AS_IS without proof.
    g = c.get("material_process_graph")
    if not isinstance(g, dict):
        raise RuntimeError("MATERIAL_PROCESS_GRAPH_REQUIRED")

    g["edges"] = [
        edge(
            "EDGE-CREATE-REGISTER", "LC01", "LC03", "DATA_CONTRACT", "OBSERVED_OPEN",
            "proposed://PROFILE_RELEASE_CONTRACT_V1/create_materialization",
            ["EV-LC-004","EV-LC-009","EV-LC-010","EV-LC-016","EV-LC-022"],
            producer_refs=["EV-LC-022"], readback_refs=["EV-LC-010"],
            route=proof("OBSERVED_FAIL", ["EV-LC-004","EV-LC-016","EV-LC-022"]),
            currentness=proof("OBSERVED_PASS", ["EV-LC-010"]),
            terminality=proof("OBSERVED_FAIL", ["EV-LC-008","EV-LC-009"]),
            identity=proof("OBSERVED_FAIL", ["EV-LC-009","EV-LC-010"]),
            rollback=proof("OBSERVED_FAIL", ["EV-LC-006","EV-LC-021"]),
        ),
        edge(
            "EDGE-UPDATE-MATERIALIZE", "LC02", "LC03", "STATE_TRANSITION", "OBSERVED_OPEN",
            "proposed://PROFILE_RELEASE_CONTRACT_V1/update_materialization",
            ["EV-LC-006","EV-LC-012","EV-LC-024"],
            producer_refs=["EV-LC-024"], readback_refs=["EV-LC-012"],
            route=proof("OBSERVED_FAIL", ["EV-LC-006","EV-LC-012","EV-LC-024"]),
            currentness=proof("OBSERVED_PASS", ["EV-LC-024"]),
            terminality=proof("OBSERVED_PASS", ["EV-LC-012"]),
            identity=proof("OBSERVED_FAIL", ["EV-LC-006","EV-LC-024"]),
            rollback=proof("OBSERVED_FAIL", ["EV-LC-006","EV-LC-021"]),
        ),
        edge(
            "EDGE-MATERIALIZE-QUALIFY", "LC03", "LC04", "CONTROL_FLOW", "PROPOSED_ONLY",
            "proposed://PROFILE_RELEASE_QUALIFICATION_BINDING_V1", [],
            next_gate="QUALIFICATION_LIFECYCLE",
            proposed_next_consumer="proposed://PROFILE_RELEASE_QUALIFICATION_BINDING_V1/QUALIFICATION_LIFECYCLE",
        ),
        edge(
            "EDGE-QUALIFY-PROMOTE", "LC04", "LC05", "AUTHORITY", "OBSERVED_OPEN",
            "proposed://PROFILE_RELEASE_ACCEPTANCE_LAYERS_V1",
            ["EV-LC-006","EV-LC-035","EV-LC-036"],
            enforcement_refs=["EV-LC-036"],
            route=proof("OBSERVED_FAIL", ["EV-LC-006"]),
            identity=proof("OBSERVED_FAIL", ["EV-LC-035"]),
        ),
        edge(
            "EDGE-PROMOTE-BOOTSTRAP", "LC05", "LC06", "CONTROL_FLOW", "OBSERVED_OPEN",
            "proposed://PROFILE_RELEASE_TRANSITION_POLICY_V1/promote_to_bootstrap",
            ["EV-LC-011","EV-LC-018"],
            consumer_refs=["EV-LC-018"],
            route=proof("OBSERVED_FAIL", ["EV-LC-011","EV-LC-018"]),
        ),
        edge(
            "EDGE-BOOTSTRAP-REFRESH", "LC06", "LC07", "RUNTIME_BINDING", "OBSERVED_OPEN",
            "proposed://PROFILE_RELEASE_CONTRACT_V1/runtime_release_binding",
            ["EV-LC-015","EV-LC-025","EV-LC-026","EV-LC-027","EV-LC-030"],
            producer_refs=["EV-LC-025"], transport_refs=["EV-LC-026","EV-LC-027"],
            consumer_refs=["EV-LC-015"], readback_refs=["EV-LC-015"],
            currentness=proof("OBSERVED_FAIL", ["EV-LC-015","EV-LC-025"]),
            identity=proof("OBSERVED_FAIL", ["EV-LC-015","EV-LC-030"]),
        ),
        edge(
            "EDGE-REFRESH-VERIFY", "LC07", "LC08", "CONTROL_FLOW", "OBSERVED_OPEN",
            "proposed://PROFILE_RELEASE_CONTRACT_V1/post_refresh_reconcile",
            ["EV-LC-018","EV-LC-025"],
            producer_refs=["EV-LC-025"], consumer_refs=["EV-LC-018"],
            next_gate="PROFILE_RUNTIME_CANARY_REQUIRED",
            proposed_next_consumer="proposed://GESTION_RELEASE_PERFIL_LF/runtime_canary_consumer",
            currentness=proof("OBSERVED_FAIL", ["EV-LC-018","EV-LC-025"]),
            terminality=proof("OBSERVED_FAIL", ["EV-LC-018"]),
        ),
        edge(
            "EDGE-VERIFY-EXECUTE", "LC08", "LC09", "AUTHORITY", "OBSERVED_OPEN",
            "proposed://PROFILE_RELEASE_ACCEPTANCE_LAYERS_V1/downstream_authorization",
            ["EV-LC-028","EV-LC-029","EV-LC-030","EV-LC-034","EV-LC-035","EV-LC-036"],
            transport_refs=["EV-LC-028"], consumer_refs=["EV-LC-029"],
            enforcement_refs=["EV-LC-036"],
            route=proof("OBSERVED_FAIL", ["EV-LC-029","EV-LC-036"]),
            currentness=proof("OBSERVED_FAIL", ["EV-LC-035"]),
            terminality=proof("OBSERVED_FAIL", ["EV-LC-019","EV-LC-023"]),
            identity=proof("OBSERVED_FAIL", ["EV-LC-030","EV-LC-035"]),
        ),
        edge(
            "EDGE-EXECUTE-TERMINAL-READBACK", "LC09", "LC08", "RECOVERY", "OBSERVED_OPEN",
            "proposed://EJECUCION_PERFIL_LF/queue_terminal_bridge",
            ["EV-LC-019","EV-LC-020","EV-LC-023"],
            producer_refs=["EV-LC-023"], consumer_refs=["EV-LC-019"],
            terminality=proof("OBSERVED_FAIL", ["EV-LC-019","EV-LC-020","EV-LC-023"]),
        ),
        edge(
            "EDGE-EXECUTE-DEPRECATE", "LC09", "LC10", "STATE_TRANSITION", "PROPOSED_ONLY",
            "proposed://PROFILE_RELEASE_TRANSITION_POLICY_V1/deprecate", [],
        ),
        edge(
            "EDGE-DEPRECATE-RETIRE", "LC10", "LC11", "STATE_TRANSITION", "OBSERVED_OPEN",
            "proposed://PROFILE_RELEASE_COMPATIBILITY_WINDOW_V1/drain_then_retire",
            ["EV-LC-005","EV-LC-021"],
            consumer_refs=["EV-LC-005"],
            route=proof("OBSERVED_FAIL", ["EV-LC-005","EV-LC-021"]),
            terminality=proof("OBSERVED_FAIL", ["EV-LC-021"]),
            rollback=proof("OBSERVED_FAIL", ["EV-LC-021"]),
        ),
        edge(
            "EDGE-VERIFY-ROLLBACK", "LC08", "LC12", "RECOVERY", "OBSERVED_OPEN",
            "proposed://PROFILE_RELEASE_TRANSITION_POLICY_V1/rollback",
            ["EV-LC-006","EV-LC-021"],
            route=proof("OBSERVED_FAIL", ["EV-LC-006","EV-LC-021"]),
            rollback=proof("OBSERVED_FAIL", ["EV-LC-006","EV-LC-021"]),
        ),
        edge(
            "EDGE-ROLLBACK-REFRESH", "LC12", "LC07", "RUNTIME_BINDING", "PROPOSED_ONLY",
            "proposed://PROFILE_RELEASE_TRANSITION_POLICY_V1/rollback_refresh", [],
        ),
    ]
    return c


def merge_manifest(base_manifest, observed_manifest):
    out = copy.deepcopy(base_manifest)
    if not isinstance(out, dict) or not isinstance(out.get("evidence"), list):
        raise RuntimeError("BASE_EVIDENCE_MANIFEST_INVALID")
    seen = {x.get("evidence_id") for x in out["evidence"] if isinstance(x, dict)}
    for row in observed_manifest.get("evidence", []):
        if isinstance(row, dict) and row.get("evidence_id") not in seen:
            out["evidence"].append(copy.deepcopy(row))
            seen.add(row.get("evidence_id"))
    out["bundle_id"] = "SRCR-V06-LIFECYCLE-MERGED-EVIDENCE-20260922"
    out["observed_at"] = observed_manifest.get("observed_at") or out.get("observed_at")
    # Preserve the governed external-resolver producer envelope from the
    # frozen base manifest. Merging observed rows must not manufacture a new
    # producer identity.
    out["bundle_digest"] = canonical_evidence_bundle_digest(out)
    return out


def resequence_trace(trace_payload):
    out = copy.deepcopy(trace_payload)
    rows = out.get("trace")
    if not isinstance(rows, list) or not rows:
        raise RuntimeError("TRACE_REQUIRED")
    for idx, row in enumerate(rows, start=1):
        row["sequence"] = idx
    out["schema"] = "SRCR_V06_LIFECYCLE_NATIVE_RESEQUENCED_TRACE_V1"
    out["trace_count"] = len(rows)
    return out


def canonical_bytes(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-candidate", required=True)
    ap.add_argument("--base-manifest", required=True)
    ap.add_argument("--observed-manifest", required=True)
    ap.add_argument("--trace", required=True)
    ap.add_argument("--out-candidate", required=True)
    ap.add_argument("--out-manifest", required=True)
    ap.add_argument("--out-trace", required=True)
    args = ap.parse_args()

    base = json.loads(Path(args.base_candidate).read_text(encoding="utf-8"))
    base_manifest = json.loads(Path(args.base_manifest).read_text(encoding="utf-8"))
    observed = json.loads(Path(args.observed_manifest).read_text(encoding="utf-8"))
    trace = json.loads(Path(args.trace).read_text(encoding="utf-8"))

    candidate = build_candidate(base)
    manifest = merge_manifest(base_manifest, observed)
    trace_out = resequence_trace(trace)

    Path(args.out_candidate).write_text(
        json.dumps(candidate, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    Path(args.out_manifest).write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    Path(args.out_trace).write_text(
        json.dumps(trace_out, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print("V06_CANDIDATE_CANONICAL_SHA256=" + hashlib.sha256(canonical_bytes(candidate)).hexdigest())
    print("V06_CANDIDATE_FILE_SHA256=" + hashlib.sha256(Path(args.out_candidate).read_bytes()).hexdigest())
    print("V06_MERGED_MANIFEST_DIGEST=" + manifest["bundle_digest"])
    print("V06_TRACE_COUNT=" + str(len(trace_out["trace"])))


if __name__ == "__main__":
    main()
