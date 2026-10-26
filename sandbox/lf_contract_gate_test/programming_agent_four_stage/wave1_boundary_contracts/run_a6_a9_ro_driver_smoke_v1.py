"""Manual RO smoke only; explicit approved connection and expected-context files."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import stat

from analysis_a6_a9_readonly_caller_v1 import DecisionContextShadowCaller, ExpectedContext, SqlReadPort
from analysis_a6_a9_ro_transport_v1 import PsycopgReadOne


def run_smoke(read_one, expected):
    report = {"schema_version": "A6_A9_RO_DRIVER_SMOKE_V1", "state": "ERROR",
              "read_verified": False, "operational_admission": False,
              "planning_allowed": False, "execution_allowed": False,
              "persistence_allowed": False, "deployment_allowed": False}
    try:
        result = DecisionContextShadowCaller(SqlReadPort(read_one)).resolve(expected, enabled=True)
        observed = result.observation.wait(2.0)
        report["state"] = observed["state"]
        for key in ("error_code", "preview_status", "issue_count"):
            if key in observed:report[key] = observed[key]
        if observed["state"] == "OBSERVED":
            report.update(read_verified=True, context_id=expected.context_id,
                          context_sha256=expected.context_sha256)
    except Exception:
        # Do not print connection/exception strings or raw resolver payloads.
        report["error_code"] = "DRIVER_SMOKE_FAILED"
    return report


def read_json(path, *, secret=False):
    try:
        fd = os.open(Path(path), os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as exc:
        raise ValueError("SMOKE_INPUT_FILE_INVALID") from exc
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        if (not stat.S_ISREG(info.st_mode) or info.st_size > 65536
                or (secret and (info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) & 0o077))):
            raise ValueError("SMOKE_INPUT_FILE_INVALID")
        raw = stream.read(65537)
        if len(raw) > 65536:raise ValueError("SMOKE_INPUT_FILE_INVALID")
        return json.loads(raw)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--connection-file", required=True)
    parser.add_argument("--expected-file", required=True)
    args = parser.parse_args()
    try:
        connection = read_json(args.connection_file, secret=True)
        expected = ExpectedContext(**read_json(args.expected_file))
        if not expected.valid():raise ValueError("EXPECTED_CONTEXT_INVALID")
        report = run_smoke(PsycopgReadOne(connection=connection), expected)
    except Exception:
        report = {"schema_version":"A6_A9_RO_DRIVER_SMOKE_V1", "state":"ERROR",
                  "error_code":"SMOKE_INPUT_OR_CONNECTION_INVALID", "read_verified":False,
                  "operational_admission":False,"deployment_allowed":False}
    print(json.dumps(report, sort_keys=True))
    return 0 if report.get("read_verified") is True else 1


if __name__ == "__main__":
    raise SystemExit(main())
