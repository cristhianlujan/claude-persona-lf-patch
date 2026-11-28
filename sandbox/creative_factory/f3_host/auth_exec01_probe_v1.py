#!/usr/bin/env python3
"""AUTH-EXEC01 evidence probe.

Captures only the current CI test-channel provenance. It deliberately does not
upgrade historical/native runtime provenance.
"""
from __future__ import annotations

import json
import os
import sys

FIELDS = (
    "GITHUB_ACTIONS",
    "GITHUB_REPOSITORY",
    "GITHUB_SHA",
    "GITHUB_RUN_ID",
    "GITHUB_WORKFLOW",
    "GITHUB_JOB",
    "GITHUB_EVENT_NAME",
    "RUNNER_ENVIRONMENT",
)


def probe(env: dict[str, str]) -> dict:
    observed = {k: env.get(k) for k in FIELDS}
    complete = (
        observed["GITHUB_ACTIONS"] == "true"
        and all(observed[k] for k in FIELDS if k != "GITHUB_ACTIONS")
    )
    return {
        "schema_version": "AUTH_EXEC01_EVIDENCE_PROBE_V1",
        "scope": "CI_TEST_CHANNEL_ONLY",
        "current_ci_channel_attested": complete,
        "native_runtime_attested": False,
        "historical_status": "NO_ACREDITADO_HISTORICAMENTE",
        "independence_proven": False,
        "observed": observed,
    }


def self_test() -> None:
    empty = probe({})
    assert empty["current_ci_channel_attested"] is False
    assert empty["historical_status"] == "NO_ACREDITADO_HISTORICAMENTE"
    fixture = {k: "fixture" for k in FIELDS}
    fixture["GITHUB_ACTIONS"] = "true"
    positive = probe(fixture)
    assert positive["current_ci_channel_attested"] is True
    assert positive["native_runtime_attested"] is False
    assert positive["independence_proven"] is False
    print("AUTH-EXEC01-NEGATIVE|PASS")
    print("AUTH-EXEC01-POSITIVE-CI-ONLY|PASS")


if __name__ == "__main__":
    self_test()
    current = probe(dict(os.environ))
    print(json.dumps(current, sort_keys=True))
    if os.environ.get("GITHUB_ACTIONS") == "true" and not current["current_ci_channel_attested"]:
        raise SystemExit("AUTH_EXEC01_CI_PROVENANCE_INCOMPLETE")
    print("AUTH-EXEC01|NO_ACREDITADO_HISTORICAMENTE|CURRENT_CI_PROBE_OK")
