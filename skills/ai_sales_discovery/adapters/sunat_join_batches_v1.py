"""Ephemeral indexed join. The caller supplies verified source streams and consumes bounded captures."""
import json
import re
import sqlite3
import tempfile
from pathlib import Path

from sunat_company_v1 import company, batches, MONTHLY_FIELDS, REDUCED_FIELDS
from sunat_commercial_gate_v1 import commercially_admissible


def source_rows(db, slot, stream, fields, max_rows, commercial_min_workers=None):
    """Count every projected RUC, including rejected source rows, before joining.

    A rejected/duplicate RUC is stored as a NULL marker (never raw payload).
    This preserves historical duplicate poisoning while filtering early.
    """
    if slot not in ("monthly","reduced"):
        raise ValueError("SOURCE_SLOT")
    if commercial_min_workers is not None and (
        type(commercial_min_workers) is not int or commercial_min_workers < 1
    ):
        raise ValueError("SUNAT_COMMERCIAL_POLICY_REQUIRED")
    for n, (raw, proof) in enumerate(stream, start=1):
        if n > max_rows:
            raise ValueError("SOURCE_ROW_LIMIT")
        if not isinstance(raw,dict) or not all(isinstance(raw.get(k),str) for k in fields):
            raise ValueError("SOURCE_FIELDS")
        ruc = raw["RUC"].strip()
        if len(ruc) != 11 or not ruc.isascii() or not ruc.isdecimal():
            raise ValueError("INVALID_PROJECTED_RUC")
        # Preserve only the source projection. Never spool street-address fields.
        admissible = True
        if commercial_min_workers is not None:
            if slot == "monthly":
                workers = raw["NroTrab"].strip()
                admissible = (
                    re.fullmatch(r"[0-9]{1,9}", workers) is not None
                    and int(workers) >= commercial_min_workers
                    and raw["Estado"].strip().upper() == "ACTIVO"
                    and raw["Condicion"].strip().upper() == "HABIDO"
                )
            else:
                admissible = (
                    bool(raw["nombre"].strip())
                    and raw["estado"].strip().upper() == "ACTIVO"
                    and raw["condicion"].strip().upper() == "HABIDO"
                )
        record = (json.dumps([{k:raw[k] for k in fields},proof],
                             ensure_ascii=False,separators=(",",":"))
                  if admissible else None)
        db.execute(f"""INSERT INTO {slot}(ruc,record,hits) VALUES(?,?,1)
                       ON CONFLICT(ruc) DO UPDATE SET hits=hits+1,record=NULL""",(ruc,record))
    db.commit()


def joined_batches(monthly_rows, reduced_rows, *, spool_pages, max_source_rows,
                   max_batch_rows, max_batch_bytes, directory=None, commercial_min_workers=None,
                   existing_rucs=None):
    """Inputs are policy-scoped projections. Both iterators reach EOF before yielding a batch."""
    if any(type(v) is not int or v<=0 for v in
           (spool_pages,max_source_rows,max_batch_rows,max_batch_bytes)):
        raise ValueError("JOIN_POLICY")
    if commercial_min_workers is not None and (type(commercial_min_workers) is not int or commercial_min_workers < 1):
        raise ValueError('SUNAT_COMMERCIAL_POLICY_REQUIRED')
    if existing_rucs is not None:
        if commercial_min_workers is None or type(existing_rucs) not in (set, frozenset) or any(
            type(ruc) is not str or re.fullmatch(r"20[0-9]{9}",ruc) is None
            for ruc in existing_rucs
        ):
            raise ValueError("SUNAT_EXISTING_RUCS_CONTRACT")
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
            source_rows(db,"monthly",monthly_rows,MONTHLY_FIELDS,max_source_rows,
                        commercial_min_workers)
            source_rows(db,"reduced",reduced_rows,REDUCED_FIELDS,max_source_rows,
                        commercial_min_workers)
            selected = db.execute("""SELECT m.record,d.record FROM monthly m JOIN reduced d USING(ruc)
                                     WHERE m.hits=1 AND d.hits=1
                                       AND m.record IS NOT NULL AND d.record IS NOT NULL
                                     ORDER BY m.ruc""")

            def captures():
                for month, reduced in selected:
                    m, me = json.loads(month)
                    d, de = json.loads(reduced)
                    if d["nombre"].strip() and (
                        existing_rucs is None or m["RUC"].strip() not in existing_rucs
                    ):
                        item=company(m,d,me,de)
                        if commercial_min_workers is None or commercially_admissible(item,min_workers=commercial_min_workers):
                            yield item

            yield from batches(captures(),max_batch_rows,max_batch_bytes)
        finally:
            db.close()
