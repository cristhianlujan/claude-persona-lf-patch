"""Read-only candidate: pinned local SUNAT archives -> bounded dual-source join."""
import csv
import hashlib
import re
import stat
import time
import unicodedata
import zipfile
from pathlib import Path
from sunat_company_v1 import MONTHLY_FIELDS, REDUCED_FIELDS, require
from sunat_join_batches_v1 import joined_batches
from sunat_batch_plan_v1 import plan_verified_batches

LIMITS = ('zip_bytes','unpacked_bytes','line_bytes','archive_rows','ratio','cohort_keys',
          'spool_pages','max_source_rows','max_batch_rows','max_batch_bytes','seconds')


def label(s):
    return ' '.join(''.join(c for c in unicodedata.normalize('NFKD',s.upper())
                            if not unicodedata.combining(c)).split())


def decode(raw):
    try:
        return raw.decode('utf-8')
    except UnicodeDecodeError:
        return raw.decode('cp1252')


def archive_lines(source, limits, deadline, extension):
    require(all(re.fullmatch('[0-9a-f]{64}', source[k]) for k in ('zip_sha256','header_sha256')), 'SOURCE_DIGEST')
    with Path(source['path']).open('rb') as f:
        f.seek(0,2)
        require(0 < f.tell() <= limits['zip_bytes'], 'ZIP_LIMIT')
        f.seek(0)
        digest = hashlib.sha256()
        while chunk := f.read(1024*1024):
            require(time.monotonic() < deadline, 'DEADLINE')
            digest.update(chunk)
        require(digest.hexdigest() == source['zip_sha256'], 'ZIP_HASH')
        f.seek(0)
        with zipfile.ZipFile(f) as z:
            require(len(z.infolist()) == 1, 'ZIP_LAYOUT')
            i = z.infolist()[0]
            require(re.fullmatch(r'[A-Za-z0-9_.-]+', i.filename) and i.filename.lower().endswith(extension)
                    and not i.is_dir() and not stat.S_ISLNK(i.external_attr >> 16)
                    and not i.flag_bits & 1 and i.compress_type in (0,8), 'ZIP_MEMBER')
            require(0 < i.file_size <= limits['unpacked_bytes'] and i.compress_size > 0
                    and i.file_size <= limits['ratio'] * i.compress_size, 'ZIP_QUOTA')
            total = 0
            with z.open(i) as stream:
                for ordinal in range(limits['archive_rows']+2):
                    require(time.monotonic() < deadline, 'DEADLINE')
                    raw = stream.readline(limits['line_bytes']+1)
                    if not raw:
                        require(ordinal > 1 and total == i.file_size, 'ZIP_EMPTY_OR_SIZE')
                        break
                    total += len(raw)
                    require(ordinal <= limits['archive_rows'], 'ARCHIVE_ROWS')
                    require(len(raw) <= limits['line_bytes'] and total <= limits['unpacked_bytes'], 'STREAM_QUOTA')
                    line = raw.rstrip(b'\r\n')
                    if ordinal == 0:
                        require(hashlib.sha256(line).hexdigest() == source['header_sha256'], 'HEADER_HASH')
                    yield ordinal, line


def proof(source, ordinal):
    return dict(url=source['url'], zip_sha256=source['zip_sha256'],
                header_sha256=source['header_sha256'], ordinal=ordinal)


def monthly_rows(source, limits, deadline, departments, cohort, stats):
    it = archive_lines(source, limits, deadline, '.csv')
    try:
        _, h = next(it)
        cols = next(csv.reader([h.decode('utf-8-sig')], strict=True))
        require(len(cols) == len(set(cols)) and set(MONTHLY_FIELDS) <= set(cols), 'MONTHLY_SCHEMA')
        ix = [cols.index(k) for k in MONTHLY_FIELDS]
        for ordinal, line in it:
            stats['monthly_rows'] += 1
            row = next(csv.reader([line.decode('utf-8')], strict=True))
            require(len(row) == len(cols), 'MONTHLY_WIDTH')
            m = dict(zip(MONTHLY_FIELDS, (row[n] for n in ix)))
            ruc, ubigeo = m['RUC'].strip(), m['UBIGEO'].strip()
            require(re.fullmatch('[0-9]{11}',ruc), 'MONTHLY_RUC')
            if not ruc.startswith('20') or not re.fullmatch('[0-9]{6}',ubigeo) or ubigeo[:2] not in departments:
                continue
            cohort.add(ruc)
            require(len(cohort) <= limits['cohort_keys'], 'COHORT_LIMIT')
            stats['monthly_selected'] += 1
            yield m, proof(source,ordinal)
    finally:
        it.close()


def reduced_rows(source, limits, deadline, cohort, stats):
    it = archive_lines(source, limits, deadline, '.txt')
    try:
        _, h = next(it)
        cols = (decode(h).lstrip('\ufeff')).split('|')
        trailing = cols[-1] == ''
        if trailing:
            cols.pop()
        labels = [label(c) for c in cols]
        expected = ('RUC','NOMBRE O RAZON SOCIAL','ESTADO DEL CONTRIBUYENTE','CONDICION DE DOMICILIO','UBIGEO')
        require(len(labels) == len(set(labels)) and all(c in labels for c in expected), 'REDUCED_SCHEMA')
        ix = [labels.index(c) for c in expected]
        for ordinal, raw in it:
            stats['reduced_rows'] += 1
            fields = raw.split(b'|')
            key = fields[ix[0]].strip() if ix[0] < len(fields) else b''
            if not re.fullmatch(rb'20[0-9]{9}', key) or key.decode('ascii') not in cohort:
                continue
            ruc = key.decode('ascii')
            malformed = (trailing and fields[-1] != b'') or len(fields) != len(cols)+int(trailing)
            if not malformed:
                try:
                    d = dict(zip(REDUCED_FIELDS, (decode(fields[n]) for n in ix)))
                except UnicodeDecodeError:
                    malformed = True
            if malformed:
                # Poison identifiable bad keys; join excludes both lone malformed and duplicates.
                d = dict.fromkeys(REDUCED_FIELDS,'')
                d['RUC'] = ruc
                stats['reduced_quarantined'] += 1
            stats['reduced_selected'] += 1
            yield d, proof(source,ordinal)
    finally:
        it.close()


def candidate_receipt(monthly, reduced, *, departments, limits, directory=None, batch_plan=None, _staging=None, commercial_min_workers=None):
    """No publication or external I/O. Caller supplies reviewed, pinned local archives."""
    require(isinstance(limits,dict) and all(type(limits.get(k)) is int and limits[k]>0 for k in LIMITS), 'LIMITS')
    require(isinstance(departments,(list,tuple)) and departments and
            all(isinstance(d,str) and re.fullmatch('[0-9]{2}',d) for d in departments), 'SCOPE')
    for source in (monthly,reduced):
        require(isinstance(source,dict) and all(isinstance(source.get(k),str) and source[k] for k in
            ('url','path','zip_sha256','header_sha256')), 'SOURCE')
    require(re.fullmatch(r'https://www\.datosabiertos\.gob\.pe/sites/default/files/PadronRUC_[0-9]{6}\.zip',monthly['url'])
            and reduced['url']=='https://www2.sunat.gob.pe/padron_reducido_ruc.zip', 'SOURCE_URL')
    require(_staging is None or batch_plan is not None, 'STAGE_PLAN_REQUIRED')
    deadline = time.monotonic()+limits['seconds']
    cohort = set()
    stats = dict(monthly_rows=0,monthly_selected=0,reduced_rows=0,reduced_selected=0,reduced_quarantined=0)
    ms = monthly_rows(monthly,limits,deadline,departments,cohort,stats)
    rs = reduced_rows(reduced,limits,deadline,cohort,stats)
    # Commercial opt-in changes row counts and canonical batch hashes. It MUST be
    # accompanied by a separately approved commercial manifest; never reuse 479 raw batches.
    require(commercial_min_workers is None or
            (type(commercial_min_workers) is int and commercial_min_workers > 0),'COMMERCIAL_MIN_WORKERS')
    if commercial_min_workers is not None:
        require(batch_plan is not None,'COMMERCIAL_NEW_MANIFEST_REQUIRED')
    stream = joined_batches(ms,rs,**{k:limits[k] for k in ('spool_pages','max_source_rows','max_batch_rows','max_batch_bytes')},
                            directory=directory,commercial_min_workers=commercial_min_workers)
    count = batches = 0
    digest = hashlib.sha256()
    plan = None
    try:
        import json
        if batch_plan is None:
            for payload in stream:
                require(time.monotonic() < deadline, 'DEADLINE')
                count += len(json.loads(payload))
                batches += 1
                digest.update(hashlib.sha256(payload).digest())
        else:
            def bounded_stream():
                for payload in stream:
                    require(time.monotonic() < deadline, 'DEADLINE')
                    if _staging is not None:
                        _staging.append(payload)
                    yield payload
            plan = plan_verified_batches(bounded_stream(), expected=batch_plan['expected'],
                    monthly_url=monthly['url'], scope_key='LIMA_ICA', limits=batch_plan['limits'])
            count, batches = plan['rows'], plan['batches']
        require(time.monotonic() < deadline, 'DEADLINE')
    finally:
        stream.close()
        ms.close()
        rs.close()
    receipt = dict(state='CANDIDATE_READ_ONLY', source_id='PE-SUNAT-RUC', rows=count, batches=batches,
                batch_digest_sha256=plan['batch_digest_sha256'] if plan is not None else digest.hexdigest(), source_sha256=[monthly['zip_sha256'],reduced['zip_sha256']],
                stats=stats, scope=list(departments), history_requested=False, db_write_confirmed=False,
                runtime_authorized=False, rights_verified=False)
    if plan is not None:
        require(stats == batch_plan['expected']['stats'], 'PLAN_STATS_MISMATCH')
        receipt['batch_plan'] = plan
    return receipt
