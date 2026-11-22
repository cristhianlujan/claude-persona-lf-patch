"""Candidate-only manifest for verified canonical SUNAT batches. No writer or external I/O."""
import hashlib
import json
import re
from sunat_company_v1 import company


def require(ok, code):
    if not ok:
        raise ValueError(code)


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode('utf-8')


def sha(value):
    return hashlib.sha256(value).hexdigest()


def plan_verified_batches(payloads, *, expected, monthly_url, scope_key, limits):
    """Consume an entire ordered stream; return metadata only after exact QA reconciliation.

    Caller must supply payloads from the existing CRC-verified join and a trusted receipt.
    This function does not authenticate the receipt or authorize any database operation.
    """
    require(isinstance(expected, dict) and expected.get('state') == 'CANDIDATE_READ_ONLY'
            and expected.get('qa_baseline_match') is True and expected.get('source_id') == 'PE-SUNAT-RUC', 'RECEIPT')
    require(expected.get('runtime_authorized') is False and expected.get('db_write_confirmed') is False, 'RECEIPT_BOUNDARY')
    sources = expected.get('source_sha256')
    require(isinstance(sources, list) and len(sources)==2 and all(isinstance(x,str) and re.fullmatch('[0-9a-f]{64}', x) for x in sources) and sources[0]!=sources[1], 'SOURCE_HASH')
    require(isinstance(monthly_url,str) and re.fullmatch(r'https://www\.datosabiertos\.gob\.pe/sites/default/files/PadronRUC_[0-9]{6}\.zip',monthly_url), 'SOURCE_URL')
    require(scope_key=='LIMA_ICA' and sorted(expected.get('scope',[]))==['11','15'], 'SCOPE')
    require(isinstance(limits,dict) and all(type(limits.get(k)) is int and limits[k]>0 for k in ('max_rows','max_bytes','max_batches','max_total_bytes')), 'LIMITS')
    require(all(type(expected.get(k)) is int and expected[k]>0 for k in ('rows','batches')) and isinstance(expected.get('batch_digest_sha256'),str) and re.fullmatch('[0-9a-f]{64}',expected['batch_digest_sha256']), 'RECEIPT_COUNTS')
    plan=[]; count=total=0; previous=''; chain=hashlib.sha256()
    for payload in payloads:
        require(len(plan)<limits['max_batches'], 'BATCH_LIMIT')
        require(type(payload) is bytes and 0<len(payload)<=limits['max_bytes'], 'BATCH_BYTES')
        total+=len(payload); require(total<=limits['max_total_bytes'], 'TOTAL_BYTES')
        rows=json.loads(payload)
        require(isinstance(rows,list) and 0<len(rows)<=limits['max_rows'] and canonical(rows)==payload,'BATCH_SHAPE_OR_CANONICAL')
        for row in rows:
            require(isinstance(row,dict) and set(row)=={'capture','capture_sha256'},'CAPTURE_SHAPE')
            c=row['capture']; require(isinstance(c,dict) and c.get('version')=='sunat.company.v1' and c.get('source')=='SUNAT' and sha(canonical(c))==row['capture_sha256'],'CAPTURE_HASH')
            ruc=c['normalized']['ruc']; require(isinstance(ruc,str) and re.fullmatch('20[0-9]{9}',ruc) and ruc>previous,'RUC_ORDER_DUPLICATE')
            obs=c['observations']; m=obs['monthly']; r=obs['reduced']; require(m['raw']['RUC'].strip()==ruc==r['raw']['RUC'].strip(),'RUC_MISMATCH')
            require(m['evidence']['url']==monthly_url and r['evidence']['url']=='https://www2.sunat.gob.pe/padron_reducido_ruc.zip' and [m['evidence']['zip_sha256'],r['evidence']['zip_sha256']]==sources,'SNAPSHOT_MISMATCH')
            require(re.fullmatch('[0-9]{6}',m['raw']['UBIGEO'].strip()) and m['raw']['UBIGEO'].strip()[:2] in ('11','15'),'SCOPE_ROW')
            require(row==company(m['raw'],r['raw'],m['evidence'],r['evidence']),'CAPTURE_CONTRACT')
            previous=ruc
        h=sha(payload); chain.update(bytes.fromhex(h)); count+=len(rows)
        index=len(plan)+1
        key=sha(canonical(['PE-SUNAT-RUC', sources, scope_key, index]))
        plan.append(dict(batch_key=key, ordinal=index, rows=len(rows), bytes=len(payload), capture_sha256=h,
                         consulta_evidencia_ref=monthly_url+'#captura-json-sha256='+h))
    require(count==expected['rows'] and len(plan)==expected['batches'] and chain.hexdigest()==expected['batch_digest_sha256'],'TERMINAL_RECONCILIATION')
    return dict(state='CANDIDATE_PLAN_ONLY', source_id='PE-SUNAT-RUC', scope_key=scope_key, snapshot_sha256=sources,
                rows=count, batches=len(plan), total_bytes=total, batch_digest_sha256=chain.hexdigest(), plan=plan,
                runtime_authorized=False, db_write_confirmed=False)
