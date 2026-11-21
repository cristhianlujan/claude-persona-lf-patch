"""Ephemeral indexed join. The caller supplies verified source streams and consumes bounded captures."""
import json
import sqlite3
import tempfile
from pathlib import Path

from sunat_company_v1 import company, batches, MONTHLY_FIELDS, REDUCED_FIELDS


def source_rows(db, slot, stream, fields, max_rows):
    for n, (raw, proof) in enumerate(stream, start=1):
        if n > max_rows:
            raise ValueError("SOURCE_ROW_LIMIT")
        if not isinstance(raw,dict) or not all(isinstance(raw.get(k),str) for k in fields):
            raise ValueError("SOURCE_FIELDS")
        ruc = raw["RUC"].strip()
        if len(ruc) != 11 or not ruc.isascii() or not ruc.isdecimal():
            raise ValueError("INVALID_PROJECTED_RUC")
        # Preserve only the source projection. Never spool street-address fields.
        record = json.dumps([{k:raw[k] for k in fields},proof],ensure_ascii=False,separators=(",",":"))
        db.execute(f"""INSERT INTO {slot}(ruc,record,hits) VALUES(?,?,1)
                       ON CONFLICT(ruc) DO UPDATE SET hits=hits+1,record=NULL""",(ruc,record))
    db.commit()


def joined_batches(monthly_rows, reduced_rows, *, spool_pages, max_source_rows,
                   max_batch_rows, max_batch_bytes, directory=None):
    """Inputs are policy-scoped projections. Both iterators reach EOF before yielding a batch."""
    if any(type(v) is not int or v<=0 for v in
           (spool_pages,max_source_rows,max_batch_rows,max_batch_bytes)):
        raise ValueError("JOIN_POLICY")
    with tempfile.TemporaryDirectory(dir=directory) as work:
        db = sqlite3.connect(Path(work)/"join.tmp")
        try:
            db.execute("PRAGMA journal_mode=OFF")
            db.execute("PRAGMA temp_store=FILE")
            limit, = db.execute(f"PRAGMA max_page_count={spool_pages}").fetchone()
            if limit != spool_pages:
                raise ValueError("SPOOL_LIMIT")
            for table in ("monthly","reduced"):
                db.execute(f"CREATE TABLE {table}(ruc TEXT PRIMARY KEY, record TEXT, hits INTEGER NOT NULL) WITHOUT ROWID")
            source_rows(db,"monthly",monthly_rows,MONTHLY_FIELDS,max_source_rows)
            source_rows(db,"reduced",reduced_rows,REDUCED_FIELDS,max_source_rows)
            selected = db.execute("""SELECT m.record,d.record FROM monthly m JOIN reduced d USING(ruc)
                                     WHERE m.hits=1 AND d.hits=1 ORDER BY m.ruc""")

            def captures():
                for month, reduced in selected:
                    m, me = json.loads(month)
                    d, de = json.loads(reduced)
                    if d["nombre"].strip():
                        yield company(m,d,me,de)

            yield from batches(captures(),max_batch_rows,max_batch_bytes)
        finally:
            db.close()
