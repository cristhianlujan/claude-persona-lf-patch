"""Pinned-source QA orchestration only; not an admission authority or writer."""
import re
import tempfile
import time
from pathlib import Path
from sunat_download_v1 import acquire
from sunat_dual_stream_v1 import candidate_receipt, LIMITS
from sunat_company_v1 import require

EXPECTED_KEYS = ('rows','monthly_rows','monthly_selected','reduced_rows')
TRANSPORT_KEYS = ('attempts','socket_timeout','deadline_seconds','backoff_seconds','total_seconds')


def run_candidate_qa(request, *, opener=None, directory=None):
    require(isinstance(request,dict) and request.get('mode') == 'PINNED_QA_ONLY', 'QA_MODE')
    require(isinstance(request.get('evidence_ref'),str) and request['evidence_ref'].strip(), 'QA_EVIDENCE_REF')
    sources = request.get('sources')
    require(isinstance(sources,dict) and set(sources)=={'monthly','reduced'}, 'SOURCE_SET')
    for s in sources.values():
        require(isinstance(s,dict) and set(s)=={'url','zip_sha256','header_sha256'} and
                all(isinstance(s[k],str) and re.fullmatch('[0-9a-f]{64}',s[k]) for k in ('zip_sha256','header_sha256')) and
                isinstance(s['url'],str), 'SOURCE_MANIFEST')
    require(re.fullmatch(r'https://www\.datosabiertos\.gob\.pe/sites/default/files/PadronRUC_[0-9]{6}\.zip',sources['monthly']['url']) and
            sources['reduced']['url']=='https://www2.sunat.gob.pe/padron_reducido_ruc.zip', 'SOURCE_URL')
    require(sources['monthly']['zip_sha256']!=sources['reduced']['zip_sha256'], 'SOURCE_DUPLICATE')
    limits, transport, baseline, departments = (request.get(k) for k in ('limits','transport','expected','departments'))
    for value, keys, code in ((limits,LIMITS,'LIMITS'),(transport,TRANSPORT_KEYS,'TRANSPORT'),(baseline,EXPECTED_KEYS,'BASELINE')):
        require(isinstance(value,dict) and all(type(value.get(k)) is int and value[k]>0 for k in keys),code)
    require(isinstance(departments,list) and departments and all(isinstance(d,str) and re.fullmatch('[0-9]{2}',d) for d in departments)
            and len(departments)==len(set(departments)), 'SCOPE')
    deadline=time.monotonic()+transport['total_seconds']
    def remaining():
        seconds=int(deadline-time.monotonic())
        require(seconds>0,'QA_DEADLINE')
        return seconds
    with tempfile.TemporaryDirectory(dir=directory) as work:
        local, receipts = {}, {}
        for kind in ('monthly','reduced'):
            src=sources[kind]
            path=Path(work)/(kind+'.zip')
            receipts[kind]=acquire(src['url'],path,allowed_urls={src['url']},max_bytes=limits['zip_bytes'],
                attempts=transport['attempts'],socket_timeout=transport['socket_timeout'],
                deadline_seconds=min(remaining(),transport['deadline_seconds']),backoff_seconds=transport['backoff_seconds'],
                expected_sha=src['zip_sha256'],opener=opener)
            local[kind]=dict(src,path=str(path))
        receipt=candidate_receipt(local['monthly'],local['reduced'],departments=departments,
            limits=dict(limits,seconds=min(remaining(),limits['seconds'])),directory=work)
        observed=dict(rows=receipt['rows'],**{k:receipt['stats'][k] for k in EXPECTED_KEYS if k!='rows'})
        require(all(observed[k]==baseline[k] for k in EXPECTED_KEYS),'BASELINE_MISMATCH')
        remaining()
        return dict(receipt,qa_baseline=observed,qa_baseline_match=True,qa_evidence_ref=request['evidence_ref'],
                    downloads=receipts,qa_mode='PINNED_QA_ONLY')
