"""One-shot QA of the exact already-reviewed SUNAT snapshot pair, aggregate metadata only."""
import hashlib
import json
import re
from pathlib import Path
from sunat_integrated_real_probe import build_request
from sunat_candidate_run_v1 import run_candidate_qa

EVIDENCE=Path(__file__).resolve().parent/'evidence'/'sunat_integrated_qa_20261121.json'

def main():
    request=build_request()
    evidence=json.loads(EVIDENCE.read_text(encoding='utf-8'))
    prior=evidence['receipt']
    request['batch_plan']=dict(expected=prior,limits=dict(max_rows=request['limits']['max_batch_rows'],
        max_bytes=request['limits']['max_batch_bytes'],max_batches=prior['batches'],
        max_total_bytes=prior['batches']*request['limits']['max_batch_bytes']))
    result=run_candidate_qa(request)
    plan=result['batch_plan']; entries=plan['plan']
    assert plan['rows']==prior['rows'] and plan['batches']==prior['batches']
    assert plan['batch_digest_sha256']==prior['batch_digest_sha256']
    assert sum(x['rows'] for x in entries)==plan['rows']
    assert sum(x['bytes'] for x in entries)==plan['total_bytes']
    assert len({x['batch_key'] for x in entries})==plan['batches']
    assert all(set(x)=={'batch_key','ordinal','rows','bytes','capture_sha256','consulta_evidencia_ref'} for x in entries)
    assert not result['runtime_authorized'] and not result['rights_verified'] and not result['db_write_confirmed']
    digest=hashlib.sha256(json.dumps(entries,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode('utf-8')).hexdigest()
    print('SUNAT_PINNED_BATCH_PLAN_QA '+json.dumps(dict(state=plan['state'],rows=plan['rows'],batches=plan['batches'],
        total_bytes=plan['total_bytes'],batch_digest_sha256=plan['batch_digest_sha256'],
        manifest_digest_sha256=digest,source_sha256=plan['snapshot_sha256'],
        unique_batch_keys=len({x['batch_key'] for x in entries}),stats=result['stats'],
        qa_baseline_match=result['qa_baseline_match'],runtime_authorized=False,rights_verified=False,
        db_write_confirmed=False),sort_keys=True),flush=True)

if __name__=='__main__':
    try:
        main()
    except Exception as e:
        reason=str(e) if type(e) is ValueError and re.fullmatch('[A-Z_]+',str(e)) else type(e).__name__
        print('SUNAT_PINNED_BATCH_PLAN_BLOCKED '+reason,flush=True)
        raise SystemExit(1)
