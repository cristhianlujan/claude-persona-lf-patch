"""Lote 1 IG: source-only regression. The migration runs its own atomic DB canary in the Train."""
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[3]
MIGRATION=ROOT/"supabase/migrations/20261105221000_lf_ig_live_predecision_crosscheck_v1.sql"

def src():
    return MIGRATION.read_text(encoding="utf-8")

def test_pins_and_anchor_guards():
    s=src()
    assert s.count("21f59a492708a3dee9037d9a40cba1a3")>=2
    assert s.count("d79b4ff3dfe1c2da5c2fdf8929d1ea9c")==1
    assert s.count("LF_L1_EXECUTOR_ANCHOR_DRIFT")==1
    assert s.index("LF_L1_EXECUTOR_SOURCE_DRIFT")<s.index("EXECUTE candidate_definition;")
    assert s.index("LF_L1_HUMAN_BRANCH_LOST")<s.index("EXECUTE candidate_definition;")

def test_consumes_canonical_authority_without_new_classifier():
    s=src()
    assert "private.fn_lf_ig_human_decision_live_disposition_v1(v_proposal.id)" in s
    assert "SECURITY INVOKER" in s and "SECURITY DEFINER" not in s
    assert "human_queue_opened','false" in s or "'human_queue_opened',false" in s

def test_human_branch_only_for_pre_human_admission():
    s=src()
    assert "v_human:=coalesce((v_predecision->>'pre_human_admission_count')::integer,0);" in s
    assert "v_human:=0" not in s

def test_no_privilege_or_policy_effect_and_no_explicit_tx():
    s=src().upper()
    for forbidden in ("GRANT ","REVOKE ","ALTER ROLE ","CREATE ROLE ","ALTER TABLE ","UPDATE LF_OPS.","DELETE FROM ","INSERT INTO ","\nBEGIN;","\nCOMMIT;"):
        assert forbidden not in s
    assert not s.lstrip().startswith("BEGIN;")

def test_five_regex_anchors_and_canary_negatives():
    s=src()
    assert len(re.findall(r"\$re\$",s))==10
    for code in ("LF_L1_NEGATIVE_NONPASS_FALSE_PASS","LF_L1_NEGATIVE_FAKE_PROPOSAL_ACCEPTED",
                 "LF_L1_NEGATIVE_UNKNOWN_RUN_ACCEPTED","LF_L1_NEW_HELPER_ELEVATED",
                 "LF_L1_CANARY_PERSISTENCE_SIDE_EFFECT"):
        assert code in s
