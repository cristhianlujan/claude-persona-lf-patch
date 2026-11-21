#!/usr/bin/env python3
"""One-shot source QA: ephemeral ZIP, aggregate evidence only; no business activation."""
import csv, hashlib, io, json, re, sys, tempfile, urllib.request, zipfile
from pathlib import Path

URL = 'https://www.datosabiertos.gob.pe/sites/default/files/PadronRUC_202610.zip'
HEADER_SHA = 'e28e408c81fa69951aba6c4343a5b9fb73e8f37f988f6b183700f1c0e66c0966'
# Bounds of this QA experiment only; not production policy.
MAX_ZIP = 300 * 1024**2
MAX_UNPACK = 8 * 1024**3
MAX_HEADER = 8192
MAX_LINE = 65536
MAX_ENTRIES = 8

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise ValueError('REDIRECT_DENIED')

def require(ok, code):
    if not ok:
        raise ValueError(code)

def download(path):
    req = urllib.request.Request(URL, headers={'Accept-Encoding':'identity','User-Agent':'AIS30-full-qa/1.0'})
    h = hashlib.sha256(); n = 0
    with urllib.request.build_opener(NoRedirect()).open(req, timeout=30) as resp, path.open('xb') as out:
        require(resp.status == 200 and resp.geturl() == URL and resp.headers.get('Content-Encoding','identity').lower() == 'identity', 'HTTP_RESPONSE_DENIED')
        expected = resp.headers.get('Content-Length')
        require(expected is None or 0 < int(expected) <= MAX_ZIP, 'DOWNLOAD_SIZE_LIMIT')
        while True:
            b = resp.read(1024**2)
            if not b: break
            n += len(b); require(n <= MAX_ZIP, 'DOWNLOAD_SIZE_LIMIT'); h.update(b); out.write(b)
        require(n > 0 and (expected is None or n == int(expected)), 'DOWNLOAD_INCOMPLETE')
    return n, h.hexdigest()

def inspect(path, expected_header):
    with zipfile.ZipFile(path) as z:
        infos = z.infolist()
        require(0 < len(infos) <= MAX_ENTRIES and sum(i.file_size for i in infos) <= MAX_UNPACK, 'ARCHIVE_LIMIT')
        require(all(re.fullmatch(r'[A-Za-z0-9_.-]{1,100}', i.filename) and not i.flag_bits & 1 and i.compress_type in (0,8) and not i.is_dir() for i in infos), 'ENTRY_UNSUPPORTED')
        require(len({i.filename for i in infos}) == len(infos), 'ENTRY_DUPLICATE')
        candidates = [i for i in infos if i.filename.lower().endswith('.csv')]
        require(len(candidates) == 1, 'CSV_SELECTION_AMBIGUOUS')
        selected = candidates[0]
        with z.open(selected) as raw:
            header = raw.readline(MAX_HEADER + 1)
            require(header.endswith(b'\n') and len(header) <= MAX_HEADER, 'HEADER_LIMIT')
            line = header.rstrip(b'\r\n')
            require(hashlib.sha256(line).hexdigest() == expected_header, 'HEADER_HASH_MISMATCH')
            columns = next(csv.reader([line.decode('utf-8-sig')], strict=True))
            require(len(columns) == 16 and len(set(columns)) == 16 and all(re.fullmatch(r'[\w .()/\-]{1,80}', c) for c in columns), 'HEADER_LABEL_UNSUPPORTED')
            require('RUC' in columns and 'UBIGEO' in columns, 'HEADER_REQUIRED_FIELD')
            ri, ui = columns.index('RUC'), columns.index('UBIGEO')
            total = legal = lima_ica = bad_width = bad_ruc = bad_ubigeo = 0
            while True:
                data = raw.readline(MAX_LINE + 1)
                if not data: break
                require(len(data) <= MAX_LINE, 'RECORD_BYTE_LIMIT')
                total += 1
                row = next(csv.reader([data.decode('utf-8')], strict=True))
                if len(row) != len(columns): bad_width += 1; continue
                ruc = row[ri].strip()
                if not re.fullmatch(r'[0-9]{11}', ruc): bad_ruc += 1; continue
                if not ruc.startswith('20'): continue
                legal += 1
                u = row[ui].strip()
                if not re.fullmatch(r'[0-9]{6}', u): bad_ubigeo += 1; continue
                if u[:2] in ('15','11'): lima_ica += 1
        for i in infos:
            if i == selected: continue
            with z.open(i) as other:
                while other.read(1024**2): pass
        require(total > 0, 'NO_RECORDS')
        return dict(columns=columns, header_sha256=expected_header, archive_crc_verified=True, entries=len(infos), unpacked_bytes=sum(i.file_size for i in infos), records=total, prefix20=legal, prefix20_lima_ica=lima_ica, bad_width=bad_width, bad_ruc=bad_ruc, prefix20_bad_ubigeo=bad_ubigeo)

def self_test():
    header = 'RUC,UBIGEO,' + ','.join('F'+str(i) for i in range(14))
    digest = hashlib.sha256(header.encode()).hexdigest()
    with tempfile.TemporaryDirectory() as d:
        p = Path(d)/'fixture.zip'
        suffix = ',' + ','.join(['x']*14) + '\n'
        with zipfile.ZipFile(p,'w',compression=zipfile.ZIP_DEFLATED) as z:
            z.writestr('fixture.csv',header+'\n'+'20000000001,150101'+suffix+'10000000001,110101'+suffix+'20000000002,999999'+suffix+'bad\n')
        r = inspect(p,digest)
        assert (r['records'],r['prefix20'],r['prefix20_lima_ica'],r['bad_width']) == (4,2,1,1)
        try: inspect(p,'0'*64)
        except ValueError as e: assert str(e) == 'HEADER_HASH_MISMATCH'
        else: raise AssertionError('hash guard did not reject')
        with zipfile.ZipFile(p,'a') as z: z.writestr('other.csv','x')
        try: inspect(p,digest)
        except ValueError as e: assert str(e) == 'CSV_SELECTION_AMBIGUOUS'
        else: raise AssertionError('selection guard did not reject')
    print('PASS_SUNAT_FULL_ARCHIVE_FIXTURE 3')

if __name__ == '__main__':
    try:
        if sys.argv[1:] == ['--self-test']: self_test()
        elif not sys.argv[1:]:
            with tempfile.TemporaryDirectory() as d:
                p = Path(d)/'source.zip'; n, sha = download(p)
                result = inspect(p,HEADER_SHA)
                print('SUNAT_FULL_ARCHIVE_QA '+json.dumps(dict(zip_bytes=n,zip_sha256=sha,**result),ensure_ascii=True,sort_keys=True))
        else: raise ValueError('ARGUMENT_INVALID')
    except Exception as e:
        reason = str(e) if type(e) is ValueError and re.fullmatch('[A-Z_]+',str(e)) else type(e).__name__
        print('SUNAT_FULL_ARCHIVE_BLOCKED '+reason)
        raise SystemExit(1)
