#!/usr/bin/env python3
"""Independent recovery hook for the IG006/IG007 generic-runner transport probe.

Always prefer the official exact rollback. Safety restore is a last-resort compensating
control and never converts a failed canary into PASS.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import sys

import input_governance_ig006_ig007_exact_v2_adapter as a

BASELINE = {
    "rebind": "1bbf57bb5f51fff22e540664a3fe4e07a547a5e62b855c69abb2f981e5d92c79",
    "assertions": "d02e3d07523debdb2acf38f46a7ebfd4c0b7d8d5238ed4b5d13de3581e9d4822",
    "rebind_assertion": "b3ab572553e592fa8e8c64b9031ec741936995be67c2c469c2a0834ce11d6f9e",
    "guard": "d000493dce8f7d25139c20c75025a0a0c6dd5041547f6469aecf6d373acad574",
    "execute": "3290e752c27a46a089ed93d9a15769b7b9ca416f00d389c681431fde977da588",
}


def baseline_state() -> dict:
    raw = a.docker_psql("""
    select json_build_object(
      'rebind',encode(extensions.digest(convert_to(pg_get_functiondef('programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure),'UTF8'),'sha256'),'hex'),
      'assertions',encode(extensions.digest(convert_to(pg_get_functiondef('programacion.fn_input_v58_build_assertions(bigint,bigint,text)'::regprocedure),'UTF8'),'sha256'),'hex'),
      'rebind_assertion',encode(extensions.digest(convert_to(pg_get_functiondef('programacion.fn_input_rebind_assertion(bigint,text,jsonb)'::regprocedure),'UTF8'),'sha256'),'hex'),
      'guard',encode(extensions.digest(convert_to(pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert()'::regprocedure),'UTF8'),'sha256'),'hex'),
      'execute',encode(extensions.digest(convert_to(pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure),'UTF8'),'sha256'),'hex')
    )::text;
    """)
    import json
    return json.loads(raw)


def require_baseline() -> None:
    got = baseline_state()
    if got != BASELINE:
        raise a.base.AdapterError("RECOVERY_BASELINE_SHA_MISMATCH")


def safety_restore() -> None:
    # This block executes only for the exact reversible candidate: all four objects,
    # request-local guard anchor, and baseline backup SHA must match.
    a.docker_psql("""
    do $s$
    declare n int; g text; bk text;
    begin
      select count(*) into n from pg_proc p join pg_namespace x on x.oid=p.pronamespace
      where x.nspname='programacion' and p.proname in (
        'fn_guard_input_family_assessment_insert_baseline_ig007_v1',
        'fn_input_rebind_assertion_cached_v1',
        'fn_input_v58_build_assertions_cached_v1',
        'fn_input_governance_curator_rebind_candidate_v1');
      if n<>4 then raise exception 'S28_RECOVERY_FORWARD_OBJECT_COUNT:%',n; end if;
      select pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert()'::regprocedure),
             pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert_baseline_ig007_v1()'::regprocedure)
        into g,bk;
      if position('lf.input_screen_canonical_graph_v1' in g)=0 then raise exception 'S28_RECOVERY_GUARD_NOT_CANDIDATE'; end if;
      if encode(extensions.digest(convert_to(replace(bk,'fn_guard_input_family_assessment_insert_baseline_ig007_v1','fn_guard_input_family_assessment_insert'),'UTF8'),'sha256'),'hex')<>'d000493dce8f7d25139c20c75025a0a0c6dd5041547f6469aecf6d373acad574' then
        raise exception 'S28_RECOVERY_BACKUP_SHA_DRIFT';
      end if;
      bk:=replace(bk,'CREATE OR REPLACE FUNCTION programacion.fn_guard_input_family_assessment_insert_baseline_ig007_v1()','CREATE OR REPLACE FUNCTION programacion.fn_guard_input_family_assessment_insert()');
      execute bk;
      drop function programacion.fn_input_governance_curator_rebind_candidate_v1(integer,text,text,boolean);
      drop function programacion.fn_input_v58_build_assertions_cached_v1(bigint,bigint,text,jsonb);
      drop function programacion.fn_input_rebind_assertion_cached_v1(bigint,text,jsonb,jsonb);
      drop function programacion.fn_guard_input_family_assessment_insert_baseline_ig007_v1();
      raise notice 'S28_RECOVERY_SAFETY_RESTORE_APPLIED';
    end;
    $s$;
    """)
    require_baseline()


def recover(work: Path) -> None:
    state = a.base.ledger_state()
    if state in ({"f": 0, "r": 0, "objects": 0}, {"f": 1, "r": 1, "objects": 0}):
        require_baseline()
        a.phase_post_readback(work)
        print("RECOVERY_NOT_REQUIRED_ZERO_RESIDUE_PASS")
        return

    if state == {"f": 1, "r": 0, "objects": 0}:
        require_baseline()
        a.phase_rollback(work)
        a.phase_post_readback(work)
        print("RECOVERY_LEDGER_CLOSE_AFTER_PRIOR_SAFETY_FINALIZER_PASS")
        return

    if state != {"f": 1, "r": 0, "objects": 4}:
        raise a.base.AdapterError(f"RECOVERY_UNSUPPORTED_STATE:{state}")

    try:
        a.phase_rollback(work)
    except Exception as exact_error:
        print(f"RECOVERY_EXACT_ROLLBACK_FAILED:{type(exact_error).__name__}", file=sys.stderr)
        safety_restore()
        # The fresh rollback migration accepts the verified safety-finalized state,
        # so the second exact attempt closes the ledger without re-opening candidate runtime.
        a.phase_rollback(work)

    a.phase_post_readback(work)
    print("RECOVERY_ZERO_RESIDUE_PASS")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workdir", type=Path, required=True)
    args = parser.parse_args()
    try:
        recover(args.workdir)
        return 0
    except Exception as exc:
        print(f"FAIL_RECOVERY:{type(exc).__name__}:{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
