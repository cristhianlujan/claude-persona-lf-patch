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
            retire_idx = next((i for i, x in enumerate(stages) if isinstance(x, dict) and "RETIRE" in str(x.get("stage", "")).upper()), None)
            drain = {
                "stage": "T4-COMPAT-DRAIN",
                "entry_condition": "Release is deprecated/superseded and no-new-adoption is enforced.",
                "actions": [
                    "Inventory every active consumer against the exact deprecated release identity.",
                    "Keep existing consumers on the exact release while preventing new bindings.",
                    "Re-read consumer inventory after migration/rebinding actions.",
                ],
                "exit_condition": "Authoritative active-consumer inventory is zero and readback is current.",
                "rollback": "Cancel retirement enablement and remain in deprecated/superseded drain state; do not restore new adoption implicitly.",
            }
            if not any(isinstance(x, dict) and x.get("stage") == drain["stage"] for x in stages):
                if retire_idx is None:
                    stages.append(drain)
                else:
                    stages.insert(retire_idx, drain)
                    if isinstance(stages[retire_idx + 1], dict):
                        stages[retire_idx + 1]["stage"] = "T5-RETIRE-ENABLE"

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
