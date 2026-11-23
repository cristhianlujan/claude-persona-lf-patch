#!/usr/bin/env python3
"""B25/B28 behavioral SQL mutants on disposable PG17 only.

Two candidates deliberately bypass protection and its own source-postcheck;
a mutant counts as killed ONLY by the expected negative assertion from the
SQL test, NOT by invalid SQL, preimage drift or other error.
"""
from __future__ import annotations
import os
import pathlib
import re
import subprocess
import tempfile

ROOT=pathlib.Path(__file__).resolve().parent
CF=ROOT.parent
SRC=(ROOT/'001_saly_delivery_attestation_guard_candidate.sql').read_text()
TEST=ROOT/'test_attestation_pg17.sql'
FIXTURE=CF/'queue_v02'/'fixture_pg17.sql'

def run(sqlfile: pathlib.Path, check=True):
    return subprocess.run(['psql','-X','-q','-v','ON_ERROR_STOP=1','-f',str(sqlfile)],
                          text=True,capture_output=True,timeout=75,check=check)

def main():
    if os.environ.get('PGDATABASE')!='saly_queue_test' or os.environ.get('PGHOST') not in ('127.0.0.1','localhost'):
        raise RuntimeError('BLOCK_MUTANTS_NON_DISPOSABLE_DB')
    if os.environ.get('PGPASSWORD') or os.environ.get('LF_SUPABASE_DB_PASSWORD'):
        raise RuntimeError('BLOCK_MUTANTS_DB_SECRETS')
    postre=r'DO \$post\$[\s\S]*?END \$post\$;'
    if len(re.findall(postre,SRC)) != 1:
        raise RuntimeError('MUTANT_POSTCHECK_ANCHOR')
    release_start=SRC.index('CREATE OR REPLACE FUNCTION saly.creative_queue_release_v1(')
    start=SRC.index('AND EXISTS (\n          SELECT 1 FROM saly.creative_queue_native_delivery_evidence_v1 delivery',release_start)
    end=SRC.index('\n        )',start)+len('\n        )')
    # Mutating the whole authorization predicate ensures the test is not
    # masked by the other checks within the EXISTS.
    mutations=[
       ('release_verified_gate',SRC[:start]+'AND TRUE'+SRC[end:],
        'OLD_TEXT_LEDGER_ENABLED_DONE'),
       ('text_receipt_gate',SRC.replace(
          "RAISE EXCEPTION 'CREATIVE_QUEUE_UNATTESTED_TEXT_RECEIPT_FORBIDDEN';",
          "RETURN jsonb_build_object('status','DELIVERY_RECORDED','run_id',p_run_id);",1),
        'UNATTESTED_TEXT_ACCEPTED'),
    ]
    for name,source,expected_error in mutations:
        if source==SRC:
            raise RuntimeError('MUTANT_SOURCE_UNCHANGED:'+name)
        # Disable only self-inspection of the purposely mutated source;
        # the executable SQL and the expected behavioral test must still run.
        source=re.sub(postre,'DO $post$ BEGIN NULL; END $post$;',source,count=1)
        with tempfile.TemporaryDirectory(prefix='saly-pg17-mutant-') as tmp:
            target=pathlib.Path(tmp)/'mutant.sql'
            target.write_text(source)
            run(FIXTURE)
            migration=run(target,check=False)
            if migration.returncode!=0:
                raise RuntimeError('MUTANT_FAILED_TO_COMPILE:'+name+':'+migration.stderr[-450:])
            verdict=run(TEST,check=False)
            if verdict.returncode==0:
                raise AssertionError('MUTANT_SURVIVED:'+name)
            if expected_error not in verdict.stderr or ('syntax error' in verdict.stderr.lower()):
                raise AssertionError('MUTANT_WRONG_FAILURE:'+name+':'+verdict.stderr[-650:])
        print('MUTANT_KILLED_BY_EXPECTED_ASSERTION:'+name+':'+expected_error,flush=True)

if __name__=='__main__':
    main()
