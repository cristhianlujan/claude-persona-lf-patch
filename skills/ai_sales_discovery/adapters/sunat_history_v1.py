"""Earliest verified monthly observation for a bounded cohort of RUCs."""
import argparse
import calendar
import csv
import hashlib
import json
import re
import zipfile
from datetime import date
from pathlib import Path


def require(condition, code):
    if not condition:
        raise ValueError(code)


def month_end(period):
    require(isinstance(period, str) and re.fullmatch(r"[0-9]{4}-(0[1-9]|1[0-2])", period), "PERIOD")
    year, month = map(int, period.split("-"))
    return date(year, month, calendar.monthrange(year, month)[1])


def read_snapshot(source, cohort, policy):
    path = Path(source["path"])
    with path.open("rb") as file:
        file.seek(0, 2)
        require(0 < file.tell() <= policy["zip_bytes"], "ZIP_LIMIT")
        file.seek(0)
        require(hashlib.file_digest(file, "sha256").hexdigest() == source["sha256"], "ZIP_HASH")
        file.seek(0)
        with zipfile.ZipFile(file) as archive:
            members = archive.infolist()
            require(len(members) == 1, "ARCHIVE_LAYOUT")
            member = members[0]
            require(member.filename.lower().endswith(".csv") and not member.flag_bits & 1
                    and member.file_size <= policy["unpacked_bytes"], "ARCHIVE_MEMBER")
            found = {}
            with archive.open(member) as stream:
                def line():
                    raw = stream.readline(policy["line_bytes"] + 1)
                    require(len(raw) <= policy["line_bytes"], "LINE_LIMIT")
                    return raw.rstrip(b"\r\n") if raw else None
                header = line()
                require(header is not None and hashlib.sha256(header).hexdigest() == source["header_sha256"], "HEADER_HASH")
                columns = next(csv.reader([header.decode("utf-8-sig")], strict=True))
                require(columns.count("RUC") == 1, "RUC_COLUMN")
                idx = columns.index("RUC")
                ordinal = 0
                while (raw := line()) is not None:
                    ordinal += 1
                    require(ordinal <= policy["rows_per_archive"], "ROW_LIMIT")
                    row = next(csv.reader([raw.decode("utf-8")], strict=True))
                    require(len(row) == len(columns), "ROW_WIDTH")
                    ruc = row[idx].strip()
                    if ruc in cohort:
                        found.setdefault(ruc, ordinal)
                require(ordinal > 0, "EMPTY_SNAPSHOT")
            return found


def evaluate(request):
    policy = request["limits"]
    for key in ("zip_bytes","unpacked_bytes","line_bytes","rows_per_archive","cohort_size","snapshots"):
        require(type(policy.get(key)) is int and policy[key] > 0, "LIMITS")
    cutoff = date.fromisoformat(request["as_of"])
    rucs = request["rucs"]
    require(isinstance(rucs,list) and 0 < len(rucs) <= policy["cohort_size"]
            and all(isinstance(r,str) and re.fullmatch("[0-9]{11}",r) for r in rucs), "COHORT")
    cohort = set(rucs)
    require(len(cohort) == len(rucs), "DUPLICATE_RUC")
    sources = request["snapshots"]
    require(isinstance(sources,list) and 0 < len(sources) <= policy["snapshots"], "SNAPSHOTS")
    by_period, seen_hashes, earliest = {}, set(), {}
    for source in sorted(sources,key=lambda item:item["period"]):
        period = source["period"]
        end = month_end(period)
        require(end <= cutoff, "UNCLOSED_PERIOD")
        expected_url = "https://www.datosabiertos.gob.pe/sites/default/files/PadronRUC_" + period.replace("-","") + ".zip"
        require(source["url"] == expected_url, "SOURCE_PERIOD_URL")
        require(all(isinstance(source[k],str) and re.fullmatch("[0-9a-f]{64}",source[k])
                    for k in ("sha256","header_sha256")), "DIGEST")
        require(period not in by_period and source["sha256"] not in seen_hashes, "DUPLICATE_SNAPSHOT")
        found = read_snapshot(source, cohort, policy)
        seen_hashes.add(source["sha256"])
        by_period[period] = {k:source[k] for k in ("url","sha256","header_sha256")}
        for ruc, ordinal in found.items():
            # Presence is sufficient. Repeated rows within a period cannot increase age.
            months = (cutoff.year-end.year)*12 + cutoff.month-end.month
            months -= cutoff.day < min(end.day, calendar.monthrange(cutoff.year,cutoff.month)[1])
            earliest.setdefault(ruc,dict(first_seen_period=period,ordinal=ordinal,min_full_months=months))
    return dict(version="sunat.history.v1",as_of=cutoff.isoformat(),sources=by_period,
                records=[dict(ruc=r,**earliest.get(r,dict(first_seen_period=None,ordinal=None,min_full_months=None)))
                         for r in sorted(cohort)])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest",type=Path)
    args = parser.parse_args()
    print(json.dumps(evaluate(json.loads(args.manifest.read_text())),ensure_ascii=False))
