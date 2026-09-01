#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "learning_additional_consumer_applicability_v1.json"
CANDIDATES = ROOT / "learning_additional_consumer_capability_candidates_v1.json"
EXPECTED = {
    "PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531": "ADAPTER-MARKETPLACE-LF-CX-TRUST-20260531",
    "PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531": "ADAPTER-MARKETPLACE-LF-UX-20260531",
}


def main() -> None:
    payload = json.loads(DATA.read_text(encoding="utf-8"))
    assert payload["schema"] == "LF_LEARNING_ADDITIONAL_CONSUMER_APPLICABILITY_V1"
    assert payload["mode"] == "READ_ONLY"
    assert payload["source_authority"] == "public.v_lf_router_adapter_bindings"
    assert payload["automatic_binding"] is False
    assert payload["automatic_impact"] is False
    assert payload["production_authorized"] is False
    rows = payload["consumers"]
    assert len(rows) == 2
    seen = set()
    for row in rows:
        cid = row["consumer_id"]
        assert cid in EXPECTED
        assert cid not in seen
        seen.add(cid)
        assert row["adapter_code"] == EXPECTED[cid]
        assert row["adapter_document_status"] == "CANDIDATO"
        assert row["adapter_operational_status"] == "READ_ONLY"
        assert row["router_binding_source"] == "SUPABASE_CANONICAL_ROUTER_BINDING"
        assert row["runtime_enabled"] is False
        assert row["production_enabled"] is False
        assert row["exact_capability_binding_observed"] is False
        assert row["read_only_learning_status"] == "READY_FOR_BINDING_AFTER_EXACT_CAPABILITY_CLASSIFICATION"
        assert row["fallback"] == "NO_COMPETITIVE_CONTEXT"
    assert seen == set(EXPECTED)

    candidates = json.loads(CANDIDATES.read_text(encoding="utf-8"))
    assert candidates["schema"] == "LF_LEARNING_ADDITIONAL_CONSUMER_CAPABILITY_CANDIDATES_V1"
    assert candidates["mode"] == "READ_ONLY"
    assert candidates["selection_mode"] == "DETERMINISTIC_SOURCE_SCOPE_MATCH_ONLY"
    candidate_rows = {r["consumer_id"]: r for r in candidates["candidates"]}
    assert set(candidate_rows) == set(EXPECTED)
    for row in candidate_rows.values():
        assert set(row["candidate_capabilities"]) == {"DIGITAL_SELF_SERVICE", "PAYMENT_NO_ADEUDO"}
        assert len(row["source_scope_evidence"]) >= 5
        assert row["state"] == "READY_FOR_BINDING_REVIEW"
        assert row["exact_binding_created"] is False
        assert "PRODUCT_DIRECTION_AUTHORIZED_CURRENT" in row["required_prerequisites"]
        assert set(row["must_not_invoke_without"]).issubset(set(row["required_prerequisites"]))
    assert "EXACT_CLAIM_AUTHORITY_CURRENT" in candidate_rows["PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531"]["required_prerequisites"]
    assert candidates["selector_llm_calls"] == 0
    assert candidates["selector_round_trips"] == 0
    assert candidates["semantic_search"] is False
    assert candidates["runtime_enabled"] is False
    assert candidates["automatic_binding"] is False
    assert candidates["automatic_impact"] is False
    assert candidates["production_authorized"] is False
    print("LEARNING_ADDITIONAL_CONSUMER_APPLICABILITY=PASS consumers=2/2 capability_candidates=4 exact_bindings=0 deterministic=true no_bypass=true automatic_binding=false production_authorized=false")


if __name__ == "__main__":
    main()
