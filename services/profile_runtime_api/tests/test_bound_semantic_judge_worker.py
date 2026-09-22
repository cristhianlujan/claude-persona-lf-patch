import importlib.util
from pathlib import Path

import pytest

WORKER = Path(__file__).resolve().parents[1] / "scripts" / "bound_semantic_judge_worker.py"
spec = importlib.util.spec_from_file_location("bound_semantic_judge_worker", WORKER)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)


def scope_packet():
    item = {"id":"REQ-1","statement":"Audit exact lifecycle","source_ref":"supabase://execution/1","materiality":"MATERIAL"}
    return {
        "authorized_requirements":[item],
        "constraints":[{"id":"CON-1","statement":"Read only","source_ref":"supabase://execution/1","materiality":"MATERIAL"}],
        "forbidden_changes":[{"id":"FORB-1","statement":"No mutation","source_ref":"supabase://execution/1","materiality":"MATERIAL"}],
        "authority_precedence":["EXECUTION"],
        "related_context_refs":[],
        "source_refs":["supabase://execution/1"],
    }


def test_scope_packet_requires_stable_unique_ids():
    module.validate_scope_packet(scope_packet())
    bad = scope_packet()
    bad["constraints"][0]["id"] = "REQ-1"
    with pytest.raises(RuntimeError, match="ID_DUPLICATE"):
        module.validate_scope_packet(bad)


def test_reviewer_execution_is_distinct_and_deterministic():
    rid1 = module.reviewer_id("EXEC-PRODUCER-1", "a" * 64, "b" * 40)
    rid2 = module.reviewer_id("EXEC-PRODUCER-1", "a" * 64, "b" * 40)
    assert rid1 == rid2
    assert rid1 != "EXEC-PRODUCER-1"
    assert rid1.startswith("REVIEW-SEMANTIC-")


def test_exact_ref_rejects_mutable_revision():
    with pytest.raises(RuntimeError, match="GITHUB_REF_INVALID"):
        module.exact_github_text("github://cristhianlujan/claude-persona-lf-patch@main/path.md")


def test_result_schema_requires_independence_and_reconciliation_fields():
    required = set(module.result_schema()["required"])
    for key in (
        "reviewer_execution_id","review_input_sha256","reviewer_context_mode","review_input_classes",
        "requirement_reconciliation","change_declaration_reconciliation","scope_conformance_reconciliation",
        "invariant_results","unsupported_claims","blocking_codes",
    ):
        assert key in required


def test_input_classes_are_exact_and_no_private_context_class_exists():
    assert set(module.INPUT_CLASSES) == {
        "SCOPE_AUTHORITY_PACKET","EXACT_CANDIDATE","EVIDENCE_MANIFEST","CURRENT_AUTHORITY_REFS"
    }
    assert all("PRIVATE" not in value and "CHAT" not in value for value in module.INPUT_CLASSES)


def test_candidate_digest_uses_canonical_json():
    assert module.sha256_json({"b":2,"a":1}) == module.sha256_json({"a":1,"b":2})
