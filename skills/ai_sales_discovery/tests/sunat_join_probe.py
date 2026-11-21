#!/usr/bin/env python3
"""One-shot QA of official monthly/reduced sources. No output rows or persistence."""
from collections import Counter
import csv, hashlib, json, re, sys, tempfile, unicodedata, urllib.request, zipfile
from pathlib import Path

MONTHLY='https://www.datosabiertos.gob.pe/sites/default/files/PadronRUC_202610.zip'
REDUCED='https://www2.sunat.gob.pe/padron_reducido_ruc.zip'
MONTHLY_SHA='bf875a7fdf80c16dfee03210759f497b50a5b9c69a4774ed6fbb92e6dceed0a7'
HEADER_SHA='e28e408c81fa69951aba6c4343a5b9fb73e8f37f988f6b183700f1c0e66c0966'
# QA-only bounds, not operational defaults.
MAX_ZIP=1024**3
MAX_UNPACK=12*1024**3
MAX_LINE=65536
MAX_ROWS=30_000_000
MAX_KEYS=1_500_000

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):
        raise ValueError('REDIRECT_DENIED')

def require(ok,code):
    if not ok: raise ValueError(code)

def fetch(url,path):
    require(url in (MONTHLY,REDUCED),'SOURCE_DENIED')
    req=urllib.request.Request(url,headers={'Accept-Encoding':'identity','User-Agent':'AIS30-join-qa/1.0'})
    h=hashlib.sha256(); n=0
    with urllib.request.build_opener(NoRedirect()).open(req,timeout=30) as r, path.open('xb') as out:
        require(r.status==200 and r.geturl()==url and r.headers.get('Content-Encoding','identity').lower()=='identity','HTTP_DENIED')
        expected=r.headers.get('Content-Length')
        require(expected is None or 0<int(expected)<=MAX_ZIP,'DOWNLOAD_LIMIT')
        while True:
            b=r.read(1024**2)
            if not b: break
            n+=len(b); require(n<=MAX_ZIP,'DOWNLOAD_LIMIT'); h.update(b); out.write(b)
        require(n>0 and (expected is None or n==int(expected)),'DOWNLOAD_INCOMPLETE')
    return {'bytes':n,'sha256':h.hexdigest(),'http_last_modified':r.headers.get('Last-Modified')}

def member(z,ext):
    infos=z.infolist()
    require(len(infos)==1,'ARCHIVE_ENTRIES_UNSUPPORTED')
    i=infos[0]
    require(re.fullmatch(r'[A-Za-z0-9_.-]{1,100}',i.filename) and i.filename.lower().endswith(ext) and not i.is_dir() and not i.flag_bits&1 and i.compress_type in (0,8) and 0<i.file_size<=MAX_UNPACK,'ZIP_ENTRY_UNSUPPORTED')
    return i

def lines(raw):
    n=0
    while True:
        row=raw.readline(MAX_LINE+1)
        if not row: break
        n+=1; require(n<=MAX_ROWS+1 and len(row)<=MAX_LINE,'LINE_LIMIT')
        yield row.rstrip(b'\r\n')

def norm(s):
    return ' '.join(''.join(c for c in unicodedata.normalize('NFKD',s.upper().replace('_',' ')) if not unicodedata.combining(c)).split())

def monthly(path,header_sha,sample=None):
    data={}; duplicates=set(); counts={'rows':0,'scope_rows':0,'bad_ubigeo':0}
    with zipfile.ZipFile(path) as z, z.open(member(z,'.csv')) as raw:
        it=lines(raw); header=next(it)
        require(hashlib.sha256(header).hexdigest()==header_sha,'MONTHLY_HEADER_DRIFT')
        cols=next(csv.reader([header.decode('utf-8-sig')],strict=True))
        required=['RUC','Estado','Condicion','UBIGEO','Actividad_Economica_CIIU_revision4_Principal','NroTrab']
        require(len(cols)==len(set(cols)) and all(c in cols for c in required),'MONTHLY_HEADER_INVALID')
        ix=[cols.index(c) for c in required]
        for line in it:
            counts['rows']+=1
            row=next(csv.reader([line.decode('utf-8')],strict=True))
            require(len(row)==len(cols),'MONTHLY_WIDTH')
            ruc,status,cond,u,ciiu,workers=(row[i].strip() for i in ix)
            require(re.fullmatch(r'[0-9]{11}',ruc),'MONTHLY_RUC_INVALID')
            if not ruc.startswith('20'): continue
            if not re.fullmatch(r'[0-9]{6}',u): counts['bad_ubigeo']+=1; continue
            if u[:2] not in ('15','11'): continue
            counts['scope_rows']+=1
            if ruc in data: duplicates.add(ruc); continue
            require(len(data)<MAX_KEYS,'MONTHLY_KEY_LIMIT')
            data[ruc]=(norm(status),norm(cond),u,ciiu,workers)
            if sample is not None and len(sample) < 32:
                sample[ruc] = (dict(zip(cols, row)), counts['rows'])
    require(counts['rows']>0 and data,'MONTHLY_EMPTY')
    counts.update(unique_keys=len(data),duplicate_keys=len(duplicates))
    return data,duplicates,counts

def reduced(path, data, monthly_dups, sample=None, archives=None):
    seen={}; dup=set(); counts={'rows':0,'legal_rows':0,'matching_rows':0,'missing_name_rows':0}
    rejections = Counter()
    malformed_keys = set()
    sample_reduced = {}
    geography = {level: Counter() for level in ('department', 'province', 'district')}
    worker_forms = Counter()
    worker_literals = Counter()
    ciiu_formats = Counter()
    name_encodings = Counter()
    numeric_workers = []
    with zipfile.ZipFile(path) as z, z.open(member(z,'.txt')) as raw:
        info = member(z, '.txt')
        counts.update(unpacked_bytes=info.file_size, crc32=format(info.CRC, '08x'))
        it=lines(raw); header=next(it)
        try: hs=header.decode('utf-8-sig')
        except UnicodeDecodeError: hs=header.decode('cp1252')
        cols=hs.split('|'); trailing=cols[-1]==''
        if trailing: cols.pop()
        normalized=[norm(c) for c in cols]
        aliases=[{'RUC'},{'NOMBRE O RAZON SOCIAL','NOMBRE RAZON SOCIAL','RAZON SOCIAL'},{'ESTADO DEL CONTRIBUYENTE','ESTADO CONTRIBUYENTE','ESTADO'},{'CONDICION DE DOMICILIO','CONDICION DOMICILIO','CONDICION'},{'UBIGEO','CODIGO UBIGEO'}]
        ix=[]
        for a in aliases:
            match=[i for i,c in enumerate(normalized) if c in a]; require(len(match)==1,'REDUCED_HEADER_UNRECOGNIZED'); ix.append(match[0])
        require(len(cols)==len(set(normalized)) and len(cols)<=40,'REDUCED_HEADER_INVALID')
        counts['header'] = cols
        for line in it:
            counts['rows']+=1
            fields=line.split(b'|')
            candidate = fields[ix[0]].strip() if ix[0] < len(fields) else b''
            if trailing:
                if fields[-1] != b'':
                    rejections['trailing_delimiter'] += 1
                    if candidate.isdigit() and candidate.decode('ascii') in data:
                        malformed_keys.add(candidate.decode('ascii'))
                    continue
                fields.pop()
            if len(fields) != len(cols):
                rejections['width'] += 1
                if candidate.isdigit() and candidate.decode('ascii') in data:
                    malformed_keys.add(candidate.decode('ascii'))
                continue
            r = fields[ix[0]].strip()
            if not re.fullmatch(rb'[0-9]{11}', r):
                rejections['invalid_ruc'] += 1
                continue
            if not r.startswith(b'20'): continue
            counts['legal_rows']+=1; key=r.decode('ascii')
            if key not in data or key in monthly_dups: continue
            counts['matching_rows']+=1
            name=fields[ix[1]].strip()
            if not name: counts['missing_name_rows']+=1
            def val(i):
                try: return norm(fields[ix[i]].decode('utf-8').strip())
                except UnicodeDecodeError: return norm(fields[ix[i]].decode('cp1252').strip())
            try:
                name.decode('utf-8')
                encoding = 'ascii' if name.isascii() else 'utf8_non_ascii'
            except UnicodeDecodeError:
                try:
                    name.decode('cp1252')
                    encoding = 'cp1252_decodable_non_utf8'
                except UnicodeDecodeError:
                    encoding = 'unresolved'
            name_encodings[encoding] += 1
            if sample is not None and key in sample and encoding != 'unresolved':
                codec = 'cp1252' if encoding.startswith('cp1252') else 'utf-8'
                def decode_value(index):
                    return fields[ix[index]].decode(codec)
                sample_reduced[key] = (dict(zip(('RUC','nombre','estado','condicion','ubigeo'),
                                                 (decode_value(i) for i in range(5)))), counts['rows'])
            item=(bool(name),hashlib.sha256(name).digest(),val(2),val(3),val(4))
            if key in seen: dup.add(key); continue
            seen[key]=item
    require(counts['rows']>0,'REDUCED_EMPTY')
    good=state_diff=cond_diff=ubigeo_diff=worker_num=ciiu_present=0
    for key,item in seen.items():
        if key in malformed_keys or key in dup or not item[0]: continue
        good+=1; m=data[key]
        for level, width in [('department', 2), ('province', 4), ('district', 6)]:
            geography[level][m[2][:width]] += 1
        literal = m[4]
        # Bounded frequencies for worker tokens, never release arbitrary source text.
        token = literal if re.fullmatch(r'[ A-Za-zÁÉÍÓÚÑáéíóúñ0-9./_-]{0,32}', literal) else '<other format>'
        if not re.fullmatch(r'[0-9]+', literal) and len(worker_literals) < 128:
            worker_literals[token] += 1
        ciiu = m[3]
        if re.fullmatch(r'[0-9]{4}', ciiu):
            form = 'four_digits'
        elif re.match(r'^[0-9]{4}\s*[-: ]\s*\S', ciiu):
            form = 'code_and_description'
        elif re.fullmatch(r'[A-Za-zÁÉÍÓÚÑáéíóúñ .,/()-]{4,}', ciiu):
            form = 'text'
        elif ciiu.strip() in ('','-','N/D','ND','S/I'):
            form = 'unknown'
        else:
            form = 'other'
        ciiu_formats[form] += 1
        if re.fullmatch(r'[0-9]{1,9}', literal):
            worker_forms['integer'] += 1
            numeric_workers.append(int(literal))
        elif re.fullmatch(r'[0-9]+\s*[-–]\s*[0-9]+', literal):
            worker_forms['range'] += 1
        elif literal in ('', '-', 'N/D', 'ND', 'S/I'):
            worker_forms['unknown:' + literal] += 1
        else:
            worker_forms['other'] += 1
        state_diff+=m[0]!=item[2]; cond_diff+=m[1]!=item[3]; ubigeo_diff+=m[2]!=item[4]
        worker_num+=bool(re.fullmatch(r'[0-9]+',m[4])); ciiu_present+=bool(re.fullmatch(r'[0-9]{4}',m[3]))
    counts.update(worker_special_literals=worker_literals, ciiu_rev4_forms=ciiu_formats, name_byte_classes=name_encodings)
    counts.update(keys_with_malformed_rows=len(malformed_keys), rejected_by_reason=dict(rejections), geography=geography,
                  worker_forms=dict(worker_forms), workers_min=min(numeric_workers, default=None),
                  workers_max=max(numeric_workers, default=None))
    require(all(sum(bucket.values()) == good for bucket in geography.values()), 'GEOGRAPHY_RECONCILIATION')
    counts.update(header_sha256=hashlib.sha256(header).hexdigest(),column_count=len(cols),trailing_delimiter=trailing,matched_unique_keys=len(seen),duplicate_matched_keys=len(dup),unmatched_monthly_unique_keys=len(data)-len(monthly_dups)-len(seen),matched_unambiguous_named=good,state_diff=state_diff,condition_diff=cond_diff,ubigeo_diff=ubigeo_diff,workers_numeric=worker_num,ciiu_four_digits=ciiu_present)
    if sample is not None:
        sys.path.insert(0,str(Path(__file__).resolve().parents[1] / 'adapters'))
        from sunat_company_v1 import company, batches
        captures = []
        for key in sorted(sample_reduced.keys() - dup - monthly_dups - malformed_keys):
            month, m_ordinal = sample[key]
            red, r_ordinal = sample_reduced[key]
            if not red['nombre'].strip():
                continue
            m = dict(url=MONTHLY, zip_sha256=archives[0]['sha256'], header_sha256=HEADER_SHA, ordinal=m_ordinal)
            r = dict(url=REDUCED, zip_sha256=archives[1]['sha256'], header_sha256=counts['header_sha256'], ordinal=r_ordinal)
            captures.append(company(month,red,m,r))
        payloads = list(batches(captures,32,512*1024))
        counts['pilot_dry_run'] = {'rows':len(captures), 'batches':[{'bytes':len(p),'sha256':hashlib.sha256(p).hexdigest()} for p in payloads]}
    return counts

def self_test():
    header=b'RUC,Estado,Condicion,UBIGEO,Actividad_Economica_CIIU_revision4_Principal,NroTrab'
    red=b'RUC|NOMBRE O RAZON SOCIAL|ESTADO DEL CONTRIBUYENTE|CONDICION DE DOMICILIO|UBIGEO|DOMICILIO|\n'
    with tempfile.TemporaryDirectory() as d:
        m=Path(d)/'m.zip'; r=Path(d)/'r.zip'
        def write(p,name,b):
            with zipfile.ZipFile(p,'w',compression=zipfile.ZIP_DEFLATED) as z: z.writestr(name,b)
        write(m,'monthly.csv',header+b'\n20000000001,ACTIVO,HABIDO,150101,1234,10\n20000000002,ACTIVO,HABIDO,110101,1234,20\n20000000002,ACTIVO,HABIDO,110101,1234,20\n20000000003,ACTIVO,HABIDO,110101,1234,30\n10000000001,ACTIVO,HABIDO,150101,1234,2\n')
        data,dups,c=monthly(m,hashlib.sha256(header).hexdigest()); assert c['scope_rows']==4 and c['unique_keys']==3 and c['duplicate_keys']==1
        write(r,'reduced.txt',red+b'20000000001|EMPRESA A|BAJA|HABIDO|150101|CALLE A|\n20000000002|EMPRESA B|ACTIVO|HABIDO|110101|CALLE B|\n20000000003|EMPRESA C|ACTIVO|HABIDO|110101|CALLE C|\n20000000003|EMPRESA D|ACTIVO|HABIDO|110101|CALLE D|\n')
        x=reduced(r,data,dups); assert x['matched_unambiguous_named']==1 and x['duplicate_matched_keys']==1 and x['state_diff']==1 and x['workers_numeric']==1
        write(r,'reduced.txt',red.replace(b'RUC|',b'ID|')+b'20000000001|A|ACTIVO|HABIDO|150101|X|\n')
        try: reduced(r,data,dups)
        except ValueError as e: assert str(e)=='REDUCED_HEADER_UNRECOGNIZED'
        else: raise AssertionError('schema guard')
        write(r,'reduced.txt',red+b'20000000001|A|ACTIVO|HABIDO|150101|X\n')
        x = reduced(r,data,dups)
        assert x['rejected_by_reason'] == {'trailing_delimiter': 1} and x['matched_unique_keys'] == 0
        write(r,'reduced.txt',red+b'INVALID|A|ACTIVO|HABIDO|150101|X|\n20000000001|A|ACTIVO|HABIDO|150101|X|\n')
        x = reduced(r,data,dups)
        assert x['rejected_by_reason'] == {'invalid_ruc':1} and x['matched_unambiguous_named'] == 1
        assert x['geography']['district'] == {'150101':1} and x['worker_forms'] == {'integer':1}
    print('PASS_SUNAT_JOIN_QA 5')

def main():
    with tempfile.TemporaryDirectory() as d:
        m=Path(d)/'monthly.zip'; r=Path(d)/'reduced.zip'
        a=fetch(MONTHLY,m); require(a['sha256']==MONTHLY_SHA,'MONTHLY_SNAPSHOT_CHANGED')
        sample = {}
        data,dups,mc=monthly(m,HEADER_SHA,sample); m.unlink()
        b=fetch(REDUCED,r); rc=reduced(r,data,dups,sample,(a,b))
        print('SUNAT_JOIN_QA '+json.dumps({'monthly_archive':a,'reduced_archive':b,'monthly':mc,'reduced':rc,'crc_verified':True,'rows_published':0},sort_keys=True))

if __name__=='__main__':
    try:
        if sys.argv[1:]==['--self-test']: self_test()
        elif not sys.argv[1:]: main()
        else: raise ValueError('ARGUMENT_INVALID')
    except Exception as e:
        reason=str(e) if type(e) is ValueError and re.fullmatch('[A-Z_]+',str(e)) else type(e).__name__
        print('SUNAT_JOIN_QA_BLOCKED '+reason); raise SystemExit(1)
