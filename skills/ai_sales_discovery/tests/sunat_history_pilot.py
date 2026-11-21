"""Qualify the historical reader on the previously validated October 2026 pilot."""
import hashlib
import json
import tempfile
import zipfile
from collections import Counter
from pathlib import Path

from sunat_join_probe import (HEADER_SHA, MAX_LINE, MAX_ROWS, MAX_UNPACK, MAX_ZIP,
                              MONTHLY, MONTHLY_SHA, acquire, fetch, member, monthly, require)
from sunat_history_v1 import evaluate

PERIOD = "2023-10"
HISTORICAL = "https://www.datosabiertos.gob.pe/sites/default/files/PadronRUC_202310.zip"


def main():
    with tempfile.TemporaryDirectory() as directory:
        current = Path(directory) / "202610.zip"
        fetch(MONTHLY, current)
        sample = {}
        index, duplicates, _ = monthly(current, HEADER_SHA, sample)
        require(len(sample) == 32 and not duplicates.intersection(sample), "PILOT_DRIFT")
        del index
        current.unlink()
        archive = Path(directory) / "202310.zip"
        receipt = acquire(HISTORICAL, archive, allowed_urls={HISTORICAL}, max_bytes=MAX_ZIP,
                          attempts=3, socket_timeout=30, deadline_seconds=240, backoff_seconds=1)
        with zipfile.ZipFile(archive) as reader:
            info = member(reader, ".csv")
            with reader.open(info) as stream:
                header = stream.readline(MAX_LINE + 1)
                require(len(header) <= MAX_LINE, "HEADER_LIMIT")
                header_hash = hashlib.sha256(header.rstrip(b'\r\n')).hexdigest()
        source = dict(period=PERIOD, path=str(archive), url=HISTORICAL,
                      sha256=receipt["sha256"], header_sha256=header_hash)
        print("HISTORY_RESOURCE", json.dumps(dict(zip=receipt, header_sha256=header_hash,
              unpacked_bytes=info.file_size, crc32=format(info.CRC,"08x"))),flush=True)
        result = evaluate(dict(as_of="2026-11-21", rucs=list(sample), snapshots=[source],
                               limits=dict(zip_bytes=MAX_ZIP,unpacked_bytes=MAX_UNPACK,line_bytes=MAX_LINE,
                                           rows_per_archive=MAX_ROWS,cohort_size=32,snapshots=1)))
        confirmed = [r for r in result["records"] if r["first_seen_period"] is not None]
        print("SUNAT_HISTORY_RESULT",json.dumps(dict(as_of=result["as_of"], historical_period=PERIOD,
              cohort=32,observed=len(confirmed),unobserved=32-len(confirmed),
              months_histogram=Counter(r["min_full_months"] for r in confirmed),
              current_sha256=MONTHLY_SHA,history_sha256=receipt["sha256"],
              cohort_sha256=hashlib.sha256("\n".join(sorted(sample)).encode()).hexdigest(),
              crc_verified=True),sort_keys=True))


if __name__ == "__main__":
    main()
