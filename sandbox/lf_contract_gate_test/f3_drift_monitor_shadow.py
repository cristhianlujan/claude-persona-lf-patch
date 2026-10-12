#!/usr/bin/env python3
"""Manual shadow parity report. Read-only Postgres; never raises for drift."""
import json, os, pathlib, re, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from migration_transport_normalization import canonical, sha256, compare_exact_source

ROOT=pathlib.Path(__file__).resolve().parents[3]
PATH=re.compile(r'^(20[0-9]{12})_(.+)\\.sql$')

def compare(source, ledger):
    by_ver={}
    for path,sql in source.items():
        m=PATH.fullmatch(pathlib.PurePosixPath(path).name)
        if m: by_ver[m.group(1)]={"name":m.group(2),"path":path,"sql":sql}
    out=[]
    for version in sorted(set(by_ver)|set(ledger)):
        f=by_ver.get(version); l=ledger.get(version)
        if not f: kind="LEDGER_ONLY"
        elif not l: kind="SOURCE_ONLY"
        else:
            try:
                compare_exact_source(version=version,source_name=f["name"],source_sql=f["sql"],
                                     remote_name=l["name"],remote_sha256=sha256(canonical("\\n".join(l["statements"]))),\n                                     remote_statement_count=len(l["statements"]))
                kind="MATCH"
            except Exception as exc:
                kind="MISMATCH"
        out.append({"version":version,"source_path":f["path"] if f else None,
                    "ledger_name":l["name"] if l else None,"classification":kind})
    return {"mode":"SHADOW","read_only":True,"rows":out,"counts":{k:sum(x["classification"]==k for x in out) for k in ("MATCH","MISMATCH","SOURCE_ONLY","LEDGER_ONLY")}}

def main():
    import psycopg
    src={str(x.relative_to(ROOT)):x.read_text() for x in (ROOT/"supabase/migrations").glob("*.sql")}
    with psycopg.connect(host=os.environ["PGHOST"],port=os.environ.get("PGPORT","5432"),
                         dbname="postgres",user=os.environ["PGUSER"],password=os.environ["PGPASSWORD"],
                         sslmode="require",options="-c default_transaction_read_only=on") as conn:
        with conn.cursor() as c:
            c.execute("SELECT version,name,statements FROM supabase_migrations.schema_migrations")
            ledger={str(v):{"name":n,"statements":s} for v,n,s in c.fetchall()}
    print(json.dumps(compare(src,ledger),sort_keys=True))

if __name__=="__main__": main()
