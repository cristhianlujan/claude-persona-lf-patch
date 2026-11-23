"""Private, bounded, post-reconciliation delivery of exact canonical bytes; no persistence authority."""
import hashlib
import json
import re
import tempfile
from contextlib import contextmanager
from pathlib import Path
from sunat_batch_plan_v1 import canonical, require, sha


class _Staging:
    def __init__(self, directory, limits):
        self.root=Path(directory)
        self.limits=limits
        self.count=0
        self.total=0
        self.sealed=None

    def append(self,payload):
        require(self.sealed is None,'STAGE_SEALED')
        require(type(payload) is bytes and 0<len(payload)<=self.limits['max_bytes'],'STAGE_BYTES')
        require(self.count<self.limits['max_batches'] and
                self.total+len(payload)<=self.limits['max_total_bytes'],'STAGE_QUOTA')
        with (self.root/str(self.count+1)).open('xb') as f:
            f.write(payload)
        self.count+=1
        self.total+=len(payload)

    def _payload(self,entry):
        path=self.root/str(entry['ordinal'])
        with path.open('rb') as f:
            payload=f.read(entry['bytes']+1)
        require(len(payload)==entry['bytes'] and sha(payload)==entry['capture_sha256'],'STAGE_HASH')
        rows=json.loads(payload)
        require(isinstance(rows,list) and len(rows)==entry['rows'],'STAGE_ROWS')
        return payload

    def seal(self,receipt,expected):
        plan=receipt['batch_plan']; entries=plan['plan']
        actual=dict(rows=plan['rows'],batches=plan['batches'],total_bytes=plan['total_bytes'],
                    batch_digest_sha256=plan['batch_digest_sha256'],
                    manifest_digest_sha256=sha(canonical(entries)),source_sha256=plan['snapshot_sha256'],
                    stats=receipt['stats'])
        require(all(expected[k]==v for k,v in actual.items()),'STAGE_MANIFEST_MISMATCH')
        require(receipt['qa_baseline_match'] is True and receipt['runtime_authorized'] is False
                and receipt['db_write_confirmed'] is False and receipt['rights_verified'] is False,'STAGE_BOUNDARY')
        require(self.count==len(entries)==plan['batches'] and self.total==plan['total_bytes']
                and set(p.name for p in self.root.iterdir())=={str(i) for i in range(1,self.count+1)},'STAGE_FILE_SET')
        chain=hashlib.sha256()
        for i,entry in enumerate(entries,1):
            require(entry['ordinal']==i,'STAGE_ORDINAL')
            chain.update(hashlib.sha256(self._payload(entry)).digest())
        require(chain.hexdigest()==plan['batch_digest_sha256'],'STAGE_CHAIN')
        # Private copy: caller cannot mutate the receipt to redirect staged filenames.
        self.sealed=tuple(dict(e) for e in entries)

    def iter_verified(self):
        require(self.sealed is not None,'STAGE_NOT_VERIFIED')
        for entry in self.sealed:
            yield dict(entry),self._payload(entry)


@contextmanager
def verified_candidate_payloads(request, *, expected_manifest, opener=None, directory=None):
    """Yield metadata + one-pass bounded bytes in a private temporary area after full QA.
    
    The manifest must come from reviewed evidence fixed by a future trusted caller.
    This is not an admission authority; do not connect to a writer without server admission.
    Nothing persists after the context exits, even on mismatch or a consumer exception.
    """
    from sunat_candidate_run_v1 import run_candidate_qa
    plan=request.get('batch_plan') if isinstance(request,dict) else None
    require(isinstance(plan,dict) and isinstance(plan.get('limits'),dict),'STAGE_PLAN_REQUIRED')
    limits=plan['limits']
    require(all(type(limits.get(k)) is int and limits[k]>0 for k in
                ('max_rows','max_bytes','max_batches','max_total_bytes')),'STAGE_LIMITS')
    expected=expected_manifest
    require(isinstance(expected,dict) and expected.get('state')=='CANDIDATE_PLAN_ONLY' and
            expected.get('qa_baseline_match') is True and expected.get('runtime_authorized') is False and
            expected.get('db_write_confirmed') is False and expected.get('rights_verified') is False,'STAGE_EXPECTED')
    require(all(type(expected.get(k)) is int and expected[k]>0 for k in ('rows','batches','total_bytes'))
            and expected['batches']<=limits['max_batches'] and expected['total_bytes']<=limits['max_total_bytes']
            and expected.get('unique_batch_keys')==expected['batches'] and isinstance(expected.get('stats'),dict)
            and all(isinstance(expected.get(k),str) and re.fullmatch('[0-9a-f]{64}',expected[k]) for k in
                    ('batch_digest_sha256','manifest_digest_sha256')),'STAGE_EXPECTED_LIMITS')
    prior=plan.get('expected',{})
    require(isinstance(prior,dict) and all(expected.get(k)==prior.get(k) for k in
            ('rows','batches','batch_digest_sha256','source_sha256','stats')),'STAGE_PRIOR_MISMATCH')
    with tempfile.TemporaryDirectory(dir=directory,prefix='sunat-stage-') as work:
        stage=_Staging(work,dict(limits))
        receipt=run_candidate_qa(request,opener=opener,directory=directory,_staging=stage)
        stage.seal(receipt,expected)
        stream=stage.iter_verified()
        try:
            yield receipt,stream
        finally:
            stream.close()
