#!/usr/bin/env python3
"""M10.5 CP2: execution assurance, not a judgment that every screen is READY.

This judge checks typed canonical readback; synthetic fixtures are logic-only.
Only an independently issued authentic runtime/release receipt admits material PASS.
"""
import argparse
import json
import sys

COUNT = 13
MUST_EQUAL_COHORT = (
    "cohort_count", "fresh_completed_count", "release_bound_count",
    "source_current_count", "validator_assessed_count", "edge_identity_count",
    "edge_provenance_receipt_count", "technical_pass_count", "cp2_pass_count",
)
ALLOWED_OUTCOMES = {
    "PASS_CP2", "ERROR_TECNICO", "ERROR_PROCEDENCIA",
    "NO_EJECUTADO_VNEXT", "EN_EVALUACION_NO_ERROR",
}


def classify(data):
    if not isinstance(data, dict) or data.get("schema_version") != "IG_M105_CP2_RELEASE_READBACK_V2":
        return "BLOCK_SCHEMA"
    screens = data.get("screen_results")
    if not isinstance(screens, list) or len(screens) != COUNT:
        return "BLOCK_SCREEN_COHORT"
    ids = [row.get("pantalla_id") for row in screens if isinstance(row, dict)]
    if len(ids) != COUNT or any(type(i) is not int for i in ids) or len(set(ids)) != COUNT:
        return "BLOCK_SCREEN_IDENTITY"
    if any(row.get("cp2") not in ALLOWED_OUTCOMES or
           row.get("technical") not in {"PASS_TECNICO", "ERROR_TECNICO",
                                        "NO_RUN", "IN_PROGRESS",
                                        "IN_PROGRESS_OR_POLICY_HOLD",
                                        "HOLD_NEEDS_PROVENANCE"} for row in screens):
        return "BLOCK_RESULT_CODE"
    if any(type(data.get(k)) is not int for k in MUST_EQUAL_COHORT):
        return "BLOCK_COUNTS_SHAPE"
    for name in ("technical_error_count", "cp2_provenance_error_count", "cp2_not_executed_count",
                 "cp2_pending_count", "semantic_rejections_recorded",
                 "evaluation_holds_recorded", "not_applicable_recorded"):
        if type(data.get(name)) is not int or data[name] < 0:
            return "BLOCK_COUNTS_SHAPE"
    actual = {key: sum(row.get("cp2") == key for row in screens) for key in ALLOWED_OUTCOMES}
    if actual["PASS_CP2"] != data["cp2_pass_count"] or \
       actual["ERROR_PROCEDENCIA"] != data["cp2_provenance_error_count"] or \
       actual["NO_EJECUTADO_VNEXT"] != data["cp2_not_executed_count"] or \
       actual["EN_EVALUACION_NO_ERROR"] != data["cp2_pending_count"]:
        return "BLOCK_INCONSISTENT_VERDICTS"
    if sum(row.get("technical") == "PASS_TECNICO" for row in screens) != data["technical_pass_count"]:
        return "BLOCK_INCONSISTENT_TECHNICAL_COUNT"
    # A rejection, legitimate hold or N/A is a semantic output, not an engine exception.
    if data["technical_error_count"] or actual["ERROR_TECNICO"]:
        return "BLOCK_TRUE_ENGINE_ERROR"
    if data["cp2_provenance_error_count"]:
        return "BLOCK_REAL_VNEXT_PROVENANCE_ERROR"
    if data["cp2_pending_count"]:
        return "BLOCK_EVALUATION_IN_PROGRESS"
    if data["cp2_not_executed_count"]:
        return "BLOCK_VNEXT_NOT_EXECUTED"
    if data.get("current_release") in (None, "", data.get("previous_release")) or \
       not data.get("previous_release") or not data.get("current_manifest_sha256"):
        return "BLOCK_REAL_VNEXT_RELEASE_MISSING"
    for key in MUST_EQUAL_COHORT:
        if data[key] != COUNT:
            return "BLOCK_" + key.upper()
    if data.get("scope_origin") != "M105_SCOPE_SNAPSHOT_V1":
        return "BLOCK_SCOPE"
    if data.get("not_a_production_authorization") is not True:
        return "BLOCK_AUTHORIZATION_BOUNDARY"
    # Even all-green readback is not an independently attested checkpoint receipt.
    return "ELIGIBLE_UNATTESTED"


def self_test():
    base = dict(
        schema_version="IG_M105_CP2_RELEASE_READBACK_V2",
        scope_origin="M105_SCOPE_SNAPSHOT_V1",
        current_release="vNext", previous_release="vPrevious",
        current_manifest_sha256="a" * 64, not_a_production_authorization=True,
        technical_error_count=0, cp2_provenance_error_count=0,
        cp2_not_executed_count=0, cp2_pending_count=0,
        semantic_rejections_recorded=0, evaluation_holds_recorded=0,
        not_applicable_recorded=0,
        screen_results=[dict(pantalla_id=i, cp2="PASS_CP2", technical="PASS_TECNICO")
                        for i in range(1, COUNT + 1)],
    )
    base.update({k: COUNT for k in MUST_EQUAL_COHORT})
    cases = []
    def check(label, obj, expected):
        actual = classify(obj)
        assert actual == expected, (label, actual, expected)
        cases.append(label)

    check("valid runtime logic still UNATTESTED", base, "ELIGIBLE_UNATTESTED")
    # An intentionally rejected candidate, legitimate human hold and N/A are not errors.
    for label, field in (("semantic rejection", "semantic_rejections_recorded"),
                         ("human/policy hold", "evaluation_holds_recorded"),
                         ("not applicable", "not_applicable_recorded")):
        check(label, dict(base, **{field: 1}), "ELIGIBLE_UNATTESTED")
    check("bad schema", dict(base, schema_version="bad"), "BLOCK_SCHEMA")
    check("duplicate screen", dict(base, screen_results=[base["screen_results"][0]]*COUNT), "BLOCK_SCREEN_IDENTITY")
    check("no previous release", dict(base, previous_release=None), "BLOCK_REAL_VNEXT_RELEASE_MISSING")
    broken = [dict(i) for i in base["screen_results"]]
    broken[0]["cp2"] = "ERROR_TECNICO"
    check("real validator exception", dict(base, screen_results=broken,
         cp2_pass_count=COUNT-1, technical_error_count=1), "BLOCK_TRUE_ENGINE_ERROR")
    bad_provenance = [dict(i) for i in base["screen_results"]]
    bad_provenance[0]["cp2"] = "ERROR_PROCEDENCIA"
    check("bad authentic Edge proof", dict(base, screen_results=bad_provenance,
          cp2_pass_count=COUNT-1, cp2_provenance_error_count=1),
          "BLOCK_REAL_VNEXT_PROVENANCE_ERROR")
    pending = [dict(i) for i in base["screen_results"]]
    pending[0]["cp2"] = "NO_EJECUTADO_VNEXT"
    check("release not executed is not screen error", dict(base, screen_results=pending,
          cp2_pass_count=COUNT-1, cp2_not_executed_count=1), "BLOCK_VNEXT_NOT_EXECUTED")
    policy = [dict(i) for i in base["screen_results"]]
    policy[0]["cp2"] = "EN_EVALUACION_NO_ERROR"
    check("unfinished legitimate evaluation", dict(base, screen_results=policy,
          cp2_pass_count=COUNT-1, cp2_pending_count=1), "BLOCK_EVALUATION_IN_PROGRESS")
    check("count mismatch", dict(base, release_bound_count=12), "BLOCK_RELEASE_BOUND_COUNT")
    check("forged clear error count", dict(base, technical_error_count=1), "BLOCK_TRUE_ENGINE_ERROR")
    check("forged cp2 pass count", dict(base, cp2_pass_count=12), "BLOCK_INCONSISTENT_VERDICTS")
    print(json.dumps({"logical_cases": len(cases), "passed": len(cases),
                      "material_cp2_pass": False, "cases": cases}))



def verify_live(gateway):
    """A canonical service-role RPC readback, never a local fixture, may yield PASS."""
    context = gateway.call("fn_ig_m105_cp2_dispatch_context_v1")
    if not isinstance(context, dict) or context.get("status") != "AUTHORIZED_CONTEXT":
        return {"status": "BLOCK_AUTHORITY_CONTEXT"}
    if context.get("dispatch_permitted") is not True:
        return {"status": "BLOCK_SIGNED_CUTOVER_NOT_AUTHORIZED"}
    scope = context.get("scope") or {}
    release = context.get("release") or {}
    ids = scope.get("screen_ids")
    if scope.get("schema_version") != "M105_SCOPE_SNAPSHOT_V1" or \
       not isinstance(ids, list) or len(ids) != COUNT or \
       any(type(x) is not int or x <= 0 for x in ids) or len(set(ids)) != COUNT:
        return {"status": "BLOCK_CANONICAL_COHORT"}
    if not release.get("previous_version") or \
       not release.get("version") or \
       release["previous_version"] == release["version"] or \
       not isinstance(release.get("manifest_sha256"), str) or \
       len(release["manifest_sha256"]) != 64:
        return {"status": "BLOCK_REAL_RELEASE"}
    results = []
    unique_runs = set()
    for screen in ids:
        rows = gateway.call("fn_ig_m105_cp2_screen_readback_v1", {"p_pantalla_id": screen})
        if not isinstance(rows, list) or len(rows) != 1:
            return {"status": "BLOCK_READBACK_MISSING", "pantalla_id": screen}
        row = rows[0]
        if not isinstance(row, dict) or row.get("pantalla_id") != screen:
            return {"status": "BLOCK_READBACK_SCREEN_IDENTITY", "pantalla_id": screen}
        run_id = row.get("run_id")
        if type(run_id) is not int or run_id <= 0 or run_id in unique_runs:
            return {"status": "BLOCK_RUN_IDENTITY", "pantalla_id": screen}
        unique_runs.add(run_id)
        verdict = row.get("cp2_verdict")
        results.append({"pantalla_id": screen, "run_id": run_id,
                        "cp2_verdict": verdict, "technical_verdict": row.get("technical_verdict")})
    passed = sum(row["cp2_verdict"] == "PASS_CP2" and
                 row["technical_verdict"] == "PASS_TECNICO" for row in results)
    return {"status": "PASS_MATERIAL_CANONICAL" if passed == COUNT else "FAIL_MATERIAL_CANONICAL",
            "release": release["version"], "manifest_sha256": release["manifest_sha256"],
            "verified": passed, "required": COUNT, "results": results}


class CanonicalGateway:
    """No writable request or local source may stand in for the actual authority."""
    def __init__(self, endpoint, credential):
        from urllib.parse import urlsplit
        from urllib.request import Request, urlopen
        from urllib.error import HTTPError, URLError
        parts = urlsplit(endpoint)
        if parts.scheme != "https" or not parts.netloc or not credential:
            raise ValueError("CANONICAL_CONNECTION_MISSING")
        self.url = endpoint.rstrip("/")
        self.key = credential
        self.urlopen = urlopen
        self.Request = Request
        self.HTTPError = HTTPError
        self.URLError = URLError

    def call(self, name, arguments=None):
        path = "/rest/v1/rpc/" + name
        body = json.dumps(arguments or {}).encode("utf-8")
        req = self.Request(self.url + path, data=body, method="POST", headers={
            "authorization": "Bearer " + self.key, "apikey": self.key,
            "content-type": "application/json"
        })
        try:
            with self.urlopen(req, timeout=35) as response:
                raw = response.read(2_000_000)
            return json.loads(raw)
        except self.HTTPError as error:
            raise RuntimeError("CANONICAL_HTTP_" + str(error.code)) from None
        except self.URLError:
            raise RuntimeError("CANONICAL_NETWORK_ERROR") from None

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--readback")
    parser.add_argument("--verify-live", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    elif args.verify_live:
        import os
        try:
            source = CanonicalGateway(os.environ.get("IG_CANONICAL_ENDPOINT", ""),
                                      os.environ.get("IG_CANONICAL_AUTH", ""))
            result = verify_live(source)
        except (RuntimeError, ValueError) as exc:
            result = {"status": "BLOCK_CANONICAL_CONNECTOR", "error_type": type(exc).__name__}
        print(json.dumps(result, sort_keys=True))
        sys.exit(0 if result["status"] == "PASS_MATERIAL_CANONICAL" else 2)
    else:
        if not args.readback:
            parser.error("--readback required")
        with open(args.readback, encoding="utf-8") as fp:
            v = json.load(fp)
        result = classify(v)
        print(result)
        # A supplied JSON file can never cause an admitted PASS.
        sys.exit(3 if result == "ELIGIBLE_UNATTESTED" else 2)
