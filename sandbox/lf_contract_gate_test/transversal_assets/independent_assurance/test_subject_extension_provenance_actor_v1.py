#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
BEGIN = ROOT / "supabase/migrations/20261003213050_independent_assurance_subject_extension_provenance_begin_v1.sql"
SUBJECT = ROOT / "supabase/migrations/20261003213100_independent_assurance_subject_extension_v2.sql"
CLOSE = ROOT / "supabase/migrations/20261003213150_independent_assurance_subject_extension_provenance_close_v1.sql"
ACTOR = "CHATGPT-T-INDEP-PAULO-035-20261002"
OP = "REVISION_INDEPENDIENTE_ESTRATEGIA_LF"
SUBJECT_SHA = "a35c9e9f1266cd2b97f6c0034d7cccb2d5b97a6c2f7a824e3a03d3d4c159776e"


def main() -> None:
    begin = BEGIN.read_text(encoding="utf-8")
    subject = SUBJECT.read_text(encoding="utf-8")
    close = CLOSE.read_text(encoding="utf-8")
    b = begin.lower()
    s = subject.lower()
    c = close.lower()

    # The existing subject migration references one exact provenance actor.
    assert subject.count(ACTOR) >= 7
    assert OP in subject

    # The bounded predecessor materializes that exact identity before any operation-definition mutation.
    assert "fn_lf_operation_reserve_execution_v1" in b
    assert ACTOR in begin
    assert OP in begin
    assert SUBJECT_SHA in begin
    assert "operation_definition_mutation_provenance" in b
    assert "target_type" in b and "'operation'" in b
    assert "runtime_activation',false" in b
    assert "production_activation',false" in b
    assert "promotion_authorized',false" in b

    # The subject migration still owns only the in-place extension and keeps promotion deferred.
    assert "fn_lf_capability_promote_v1(" not in s
    assert "block_t_indep_expected_requalification_gate_not_observed" in s
    assert "insert into public.lf_operation_registry" not in s
    assert "insert into public.lf_router_action_registry" not in s
    assert "insert into public.lf_operation_judges" not in s

    # The successor closes only the provenance execution after proving mutation happened and
    # qualification is stale. It may not requalify or promote by itself.
    assert ACTOR in close
    assert "status='completed'" in c
    assert "block_t_indep_provenance_close_requalification_gate_not_visible" in c
    assert "lf_operation_requalification_bootstrap_v1(" not in c
    assert "lf_run_operation_qualification_v1(" not in c
    assert "fn_lf_capability_promote_v1(" not in c
    assert "runtime_activation')::boolean,false)=false" in c
    assert "production_activation')::boolean,false)=false" in c
    assert "promotion_authorized')::boolean,false)=false" in c

    print("INDEPENDENT_ASSURANCE_SUBJECT_EXTENSION_PROVENANCE_ACTOR_V1=PASS")


if __name__ == "__main__":
    main()
