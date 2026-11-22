"""One-shot aggregate QA, using the previously reviewed pair of snapshots."""
import json
import re
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'adapters'))
from sunat_candidate_run_v1 import run_candidate_qa

EVIDENCE=Path(__file__).resolve().parent/'evidence'/'sunat_202610_join_20261121.json'

def build_request():
    evidence=json.loads(EVIDENCE.read_text(encoding='utf-8'))
    m=evidence['metrics']
    return dict(mode='PINNED_QA_ONLY',evidence_ref=evidence['source'],departments=['11','15'],
        sources=dict(monthly=dict(url='https://www.datosabiertos.gob.pe/sites/default/files/PadronRUC_202610.zip',
            zip_sha256=m['monthly_archive']['sha256'],header_sha256='e28e408c81fa69951aba6c4343a5b9fb73e8f37f988f6b183700f1c0e66c0966'),
            reduced=dict(url='https://www2.sunat.gob.pe/padron_reducido_ruc.zip',zip_sha256=m['reduced_archive']['sha256'],
            header_sha256=m['reduced']['header_sha256'])),
        limits=dict(zip_bytes=1024**3,unpacked_bytes=12*1024**3,line_bytes=65536,archive_rows=30_000_000,
            ratio=500,cohort_keys=1_500_000,spool_pages=1_000_000,max_source_rows=1_500_000,
            max_batch_rows=1000,max_batch_bytes=4*1024**2,seconds=900),
        transport=dict(attempts=3,socket_timeout=30,deadline_seconds=240,backoff_seconds=1,total_seconds=1200),
        expected=dict(rows=m['reduced']['matched_unambiguous_named'],monthly_rows=m['monthly']['rows'],
            monthly_selected=m['monthly']['scope_rows'],reduced_rows=m['reduced']['rows']))

if __name__=='__main__':
    try:
        receipt=run_candidate_qa(build_request())
        print('SUNAT_INTEGRATED_QA '+json.dumps(receipt,sort_keys=True),flush=True)
    except Exception as e:
        reason=str(e) if type(e) is ValueError and re.fullmatch('[A-Z_]+',str(e)) else type(e).__name__
        print('SUNAT_INTEGRATED_QA_BLOCKED '+reason,flush=True)
        raise SystemExit(1)
