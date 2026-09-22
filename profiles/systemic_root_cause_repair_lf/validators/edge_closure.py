"""SRCR V0.6 explicit material-edge closure floor.

V0.6 does not add Lifecycle-specific rules. It makes every material edge prove
the observed producer -> transport -> consumer -> enforcement -> effect/readback
path, and separately records route, post-transition currentness, terminality,
identity and rollback proofs when those concerns apply.

Future/proposed wiring can never be used as proof that the current AS-IS edge is
closed.
"""
from __future__ import annotations

from typing import Any

V06_PACK_ID = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6"
OBSERVATION_STATUS = {"OBSERVED_CLOSED", "OBSERVED_OPEN", "UNRESOLVED", "PROPOSED_ONLY"}
DISPOSITIONS = {"REUSE_AS_IS", "IMPLEMENTABLE", "DESIGN_BLOCKING"}
PROOF_APPLICABILITY = {"REQUIRED", "NOT_APPLICABLE"}
PROOF_STATUS = {"OBSERVED_PASS", "OBSERVED_FAIL", "UNRESOLVED", "PROPOSED_ONLY", "NOT_APPLICABLE"}
PROOF_FIELDS = (
    "canonical_route_consistency",
    "post_transition_currentness",
    "terminality",
    "identity_consistency",
    "rollback_executability",
)
CORE_REF_FIELDS = (
    "producer_evidence_refs",
    "transport_evidence_refs",
    "consumer_evidence_refs",
    "enforcement_evidence_refs",
    "effect_readback_evidence_refs",
)


def _err(code: str, path: str, message: str = "") -> dict[str, str]:
    return {"code": code, "path": path, "message": message}


def _nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _string_list(value: Any, *, nonempty: bool = False) -> bool:
    if not isinstance(value, list) or any(not _nonempty(x) for x in value):
        return False
    return not nonempty or bool(value)


def _current_evidence_ids(evidence_manifest: Any) -> set[str] | None:
    if not isinstance(evidence_manifest, dict):
        return None
    rows = evidence_manifest.get("evidence")
    if not isinstance(rows, list):
        return None
    return {
        row.get("evidence_id")
        for row in rows
        if isinstance(row, dict)
        and _nonempty(row.get("evidence_id"))
        and row.get("state") == "CURRENT"
    }


def _validate_refs(
    errors: list[dict[str, str]],
    value: Any,
    path: str,
    evidence_ids: set[str] | None,
    *,
    require_nonempty: bool,
) -> None:
    if not _string_list(value, nonempty=require_nonempty):
        errors.append(_err("V06_EDGE_EVIDENCE_REFS_INVALID", path))
        return
    if evidence_ids is None:
        if value:
            errors.append(_err("V06_EDGE_EVIDENCE_UNVERIFIABLE_WITHOUT_MANIFEST", path))
        return
    for idx, ref in enumerate(value):
        if ref not in evidence_ids:
            errors.append(_err("V06_EDGE_EVIDENCE_NOT_IN_MANIFEST", f"{path}[{idx}]"))


def _validate_proof(
    errors: list[dict[str, str]],
    proof: Any,
    path: str,
    evidence_ids: set[str] | None,
    *,
    disposition: str,
) -> None:
    if not isinstance(proof, dict):
        errors.append(_err("V06_EDGE_PROOF_REQUIRED", path))
        return
    applicability = proof.get("applicability")
    status = proof.get("status")
    refs = proof.get("evidence_refs")
    if applicability not in PROOF_APPLICABILITY:
        errors.append(_err("V06_EDGE_PROOF_APPLICABILITY_INVALID", f"{path}.applicability"))
        return
    if status not in PROOF_STATUS:
        errors.append(_err("V06_EDGE_PROOF_STATUS_INVALID", f"{path}.status"))
        return

    if applicability == "NOT_APPLICABLE":
        if status != "NOT_APPLICABLE":
            errors.append(_err("V06_EDGE_NA_PROOF_STATUS_MISMATCH", f"{path}.status"))
        _validate_refs(errors, refs, f"{path}.evidence_refs", evidence_ids, require_nonempty=False)
        return

    if status == "NOT_APPLICABLE":
        errors.append(_err("V06_EDGE_REQUIRED_PROOF_CANNOT_BE_NA", f"{path}.status"))
    observed = status in {"OBSERVED_PASS", "OBSERVED_FAIL"}
    _validate_refs(errors, refs, f"{path}.evidence_refs", evidence_ids, require_nonempty=observed)

    if disposition == "REUSE_AS_IS" and status != "OBSERVED_PASS":
        errors.append(_err(
            "V06_REUSE_EDGE_PROOF_NOT_OBSERVED_PASS",
            f"{path}.status",
            "A reused current edge must be proven on the live path; proposal/unresolved state is not closure.",
        ))


def validate_edge_closure(payload: Any, evidence_manifest: Any = None) -> list[dict[str, str]]:
    if not isinstance(payload, dict) or payload.get("profile_pack_id") != V06_PACK_ID:
        return []

    errors: list[dict[str, str]] = []
    evidence_ids = _current_evidence_ids(evidence_manifest)
    graph = payload.get("material_process_graph")
    if not isinstance(graph, dict):
        return [_err("V06_MATERIAL_PROCESS_GRAPH_REQUIRED", "$.material_process_graph")]

    nodes = graph.get("nodes") if isinstance(graph.get("nodes"), list) else []
    node_ids = {
        row.get("node_id")
        for row in nodes
        if isinstance(row, dict) and _nonempty(row.get("node_id"))
    }
    edges = graph.get("edges")
    if graph.get("applies") is True and (not isinstance(edges, list) or not edges):
        return [_err("V06_MATERIAL_EDGES_REQUIRED", "$.material_process_graph.edges")]
    if not isinstance(edges, list):
        return errors

    seen: set[str] = set()
    design_blocker_ids = {
        row.get("uncertainty_id")
        for row in (payload.get("current_uncertainties") or [])
        if isinstance(row, dict)
        and row.get("impact") == "DESIGN_BLOCKING"
        and _nonempty(row.get("uncertainty_id"))
    }

    for idx, edge in enumerate(edges):
        path = f"$.material_process_graph.edges[{idx}]"
        if not isinstance(edge, dict):
            errors.append(_err("V06_MATERIAL_EDGE_INVALID", path))
            continue

        edge_id = edge.get("edge_id")
        if not _nonempty(edge_id) or edge_id in seen:
            errors.append(_err("V06_MATERIAL_EDGE_ID_INVALID", f"{path}.edge_id"))
        else:
            seen.add(edge_id)

        for field in ("from_node", "to_node"):
            value = edge.get(field)
            if value not in node_ids:
                errors.append(_err("V06_EDGE_NODE_REF_INVALID", f"{path}.{field}"))

        observation = edge.get("observation_status")
        disposition = edge.get("disposition")
        if observation not in OBSERVATION_STATUS:
            errors.append(_err("V06_EDGE_OBSERVATION_STATUS_INVALID", f"{path}.observation_status"))
        if disposition not in DISPOSITIONS:
            errors.append(_err("V06_EDGE_DISPOSITION_INVALID", f"{path}.disposition"))

        # Current AS-IS closure cannot be inferred from proposed wiring.
        if disposition == "REUSE_AS_IS" and observation != "OBSERVED_CLOSED":
            errors.append(_err("V06_REUSE_EDGE_NOT_OBSERVED_CLOSED", f"{path}.observation_status"))
        if observation == "PROPOSED_ONLY" and disposition == "REUSE_AS_IS":
            errors.append(_err("V06_PROPOSED_EDGE_CANNOT_PROVE_REUSE", f"{path}.disposition"))
        if observation == "OBSERVED_OPEN" and disposition == "REUSE_AS_IS":
            errors.append(_err("V06_OPEN_EDGE_CANNOT_BE_REUSED_AS_IS", f"{path}.disposition"))

        for field in CORE_REF_FIELDS:
            require = disposition == "REUSE_AS_IS"
            _validate_refs(errors, edge.get(field), f"{path}.{field}", evidence_ids, require_nonempty=require)

        gap_refs = edge.get("gap_evidence_refs")
        _validate_refs(
            errors,
            gap_refs,
            f"{path}.gap_evidence_refs",
            evidence_ids,
            require_nonempty=observation in {"OBSERVED_OPEN", "UNRESOLVED"},
        )

        next_gate = edge.get("next_gate")
        next_refs = edge.get("next_gate_consumer_evidence_refs")
        if next_gate is not None and not _nonempty(next_gate):
            errors.append(_err("V06_NEXT_GATE_INVALID", f"{path}.next_gate"))
        _validate_refs(
            errors,
            next_refs,
            f"{path}.next_gate_consumer_evidence_refs",
            evidence_ids,
            require_nonempty=(next_gate is not None and observation == "OBSERVED_CLOSED"),
        )
        if next_gate is not None and disposition == "REUSE_AS_IS" and not next_refs:
            errors.append(_err("V06_NEXT_GATE_CONSUMER_UNRESOLVED", f"{path}.next_gate_consumer_evidence_refs"))

        for proof_field in PROOF_FIELDS:
            _validate_proof(
                errors,
                edge.get(proof_field),
                f"{path}.{proof_field}",
                evidence_ids,
                disposition=disposition,
            )

        if disposition == "IMPLEMENTABLE" and not _nonempty(edge.get("proposed_change_ref")):
            errors.append(_err("V06_IMPLEMENTABLE_EDGE_CHANGE_REF_REQUIRED", f"{path}.proposed_change_ref"))
        if disposition != "IMPLEMENTABLE" and edge.get("proposed_change_ref") is not None and not _nonempty(edge.get("proposed_change_ref")):
            errors.append(_err("V06_PROPOSED_CHANGE_REF_INVALID", f"{path}.proposed_change_ref"))

        blocker_ref = edge.get("blocking_uncertainty_id")
        if disposition == "DESIGN_BLOCKING":
            if not _nonempty(blocker_ref):
                errors.append(_err("V06_BLOCKED_EDGE_UNCERTAINTY_REF_REQUIRED", f"{path}.blocking_uncertainty_id"))
            elif blocker_ref not in design_blocker_ids:
                errors.append(_err("V06_BLOCKED_EDGE_UNCERTAINTY_REF_INVALID", f"{path}.blocking_uncertainty_id"))

    return errors
