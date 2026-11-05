"""Issue #3665: source-only regression; the migration itself executes atomic DB assertions.
Running pytest cannot modify Supabase. A completed profile run remains required
for the migration's post-update 8/5 database canary.
"""
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[3]
MIGRATION=ROOT/"supabase/migrations/20261105184500_lf_profile_derivation_transport_issue3665_v1.sql"
SIGNATURES={
    "public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text)":"55511725602b989238f9629a27f1ddd5",
    "public.lf_profile_result_router_return_prepare_v1(text)":"8bf503bf17f038a18124783c038d9793",
    "public.lf_router_route_v1(jsonb,jsonb,boolean)":"4e5c9a76a48769dea3ec72faf5ebceb7",
    "public.lf_router_profile_after_selection_v1(jsonb,jsonb)":"1f84204588c130148c33746a901f580b",
    "public.lf_router_profile_after_selection_raw_v1(jsonb,text)":"40009812ec47f4e93b7d52a9d807b779",
    "public.lf_profile_selector_semantic_prepare_v2(text,text,jsonb,jsonb)":"af1e2fd3675de05d0f421f6f76270364",
}
def src():
    return MIGRATION.read_text(encoding="utf-8")

def test_six_exact_sources():
    s=src()
    for sig,md5 in SIGNATURES.items():
        assert f"'{sig}'" in s and f"'{md5}'" in s
    assert s.count("expected_md5,old_fragment,new_fragment,expected_occurrences")==1
    assert len(re.findall(r"'public\.lf_[^']*\([^']+\)'\s*,\s*'[0-9a-f]{32}'",s))==6

def test_atomic_preconditions_before_effect():
    s=src()
    assert s.count("DO $lf3665$")==1 and s.count("$lf3665$;")==1
    assert s.index("LF3665_SOURCE_MD5_DRIFT")<s.index("EXECUTE edited_def;")
    assert s.index("LF3665_SOURCE_ANCHOR_DRIFT")<s.index("EXECUTE edited_def;")
    assert s.index("EXECUTE edited_def;")<s.index("LF3665_VALID_DERIVATION_INVARIANT_FAILED")
    assert s.index("LF3665_ROUTE_DERIVATION_INVARIANT_FAILED")<s.index("$lf3665$;")
    for forbidden in ("GRANT ","ALTER ROLE ","CREATE ROLE ","ALTER TABLE ","UPDATE LF_OPS.","DELETE FROM "):
        assert forbidden not in s.upper()

def test_transport_scope_is_only_candidate():
    s=src()
    assert "p_stage1#>>'{alcance,source_execution_id}'" in s
    assert "'source_execution_id',v_src" in s
    assert "v_stage1_literal:=p_original_request;" in s
    assert "e.request_sha256 IS DISTINCT FROM" in s
    assert "'downstream_execution_allowed',false" in s
    assert "public.lf_router_route_v1(v_full_stage1" in s

def test_negative_and_positive_cases():
    s=src()
    for case in ("v_ready","v_null","v_fake","v_changed","v_incomplete","v_non_direct"):
        assert case+":=" in s
    for code in (
        "LF3665_EVIDENCE_SOURCE_NOT_CURRENT",
        "LF3665_VALID_DERIVATION_INVARIANT_FAILED",
        "LF3665_NEGATIVE_DERIVATION_INVARIANT_FAILED",
        "LF3665_STAGE1_VALIDATION_FAILED",
        "LF3665_ROUTE_DERIVATION_INVARIANT_FAILED",
    ):
        assert code in s
    assert "'catalog_profile_count' IS DISTINCT FROM '8'" in s
    assert s.count("'catalog_profile_count'<>'5'")==5

def test_one_migration_and_changeset():
    import json
    meta=json.loads((ROOT/"sandbox/lf_contract_gate_test/changesets/LF-ISSUE3665-DERIVATION-TRANSPORT-20261105.json").read_text(encoding="utf-8"))
    migrations=[p for p in meta["paths"] if p.startswith("supabase/migrations/")]
    assert migrations==["supabase/migrations/20261105184500_lf_profile_derivation_transport_issue3665_v1.sql"]
    assert meta["paths"][migrations[0]]=="MIGRATION"
