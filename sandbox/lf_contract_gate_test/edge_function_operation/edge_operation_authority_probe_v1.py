"""Read-only, authenticated Operations authority inspection for one Supabase Edge target.

This is a pre-execution authority resolver, NOT a deployment transport.
It does not grant approvals, attest R17, reserve an effect, access Management API,
read or print deployment credentials, or run CP2.
"""
from __future__ import annotations

import json
import os
import re
import sys
from typing import Any, Callable
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen

OPERATION = "DEPLOY_SUPABASE_EDGE_FUNCTION_LF"
ACTION = "EDGE_FUNCTION_DEPLOY"
TARGET_TYPE = "SUPABASE_EDGE_FUNCTION"
STEP_IDS = frozenset({
    "init_execution", "source_baseline", "r17_preflight", "human_authority",
    "effect_guard", "edge_deploy", "independent_readback", "close",
})
SLUG = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


class AuthorityUnavailable(Exception):
    pass


def build_live_reader(base_url: str, bearer: str) -> Callable[[str, dict[str, str]], list[dict[str, Any]]]:
    """Use only a credential supplied by an authorized runtime, not GH workflows."""
    url = urlparse(base_url.rstrip("/"))
    if url.scheme != "https" or not url.hostname or not url.hostname.endswith(".supabase.co"):
        raise AuthorityUnavailable("AUTHORITY_URL_NOT_TRUSTED")
    if not bearer.strip():
        raise AuthorityUnavailable("AUTHORITY_READ_CREDENTIAL_MISSING")
    root = base_url.rstrip("/")
    def read(table: str, params: dict[str, str]) -> list[dict[str, Any]]:
        if table not in {
            "lf_operation_registry", "lf_router_action_registry", "lf_operation_contracts",
            "lf_operation_steps", "lf_operation_step_contracts",
            "lf_operation_judges", "lf_operation_step_judge_bindings",
            "lf_eventos", "lf_operation_execution", "lf_operation_effect_guard",
        }:
            raise AuthorityUnavailable("AUTHORITY_TABLE_NOT_IN_ALLOWLIST")
        endpoint = root + "/rest/v1/" + table + "?" + urlencode(params)
        req = Request(endpoint, headers={
            "Authorization": "Bearer " + bearer,
            "apikey": bearer,
            "Accept": "application/json",
            "Cache-Control": "no-store",
        }, method="GET")
        try:
            with urlopen(req, timeout=12) as response:
                body = json.load(response)
        except Exception as exc:
            raise AuthorityUnavailable("AUTHORITY_READ_FAILED:" + table) from exc
        if not isinstance(body, list) or any(not isinstance(x, dict) for x in body):
            raise AuthorityUnavailable("AUTHORITY_RESPONSE_INVALID:" + table)
        return body
    return read


def diagnose(read: Callable[[str, dict[str, str]], list[dict[str, Any]]], target: str) -> dict:
    if not isinstance(target, str) or not SLUG.fullmatch(target):
        raise AuthorityUnavailable("TARGET_SLUG_INVALID")

    registry = read("lf_operation_registry", {"operation_code": "eq."+OPERATION, "select": "operation_code,status,lifecycle_state_code"})
    route = read("lf_router_action_registry", {"operation_code": "eq."+OPERATION, "action_code": "eq."+ACTION,
        "asset_type": "eq."+TARGET_TYPE, "select": "operation_code,status,write_allowed"})
    contract = read("lf_operation_contracts", {"operation_code": "eq."+OPERATION, "select": "operation_code,allowed"})
    steps = read("lf_operation_steps", {"operation_code": "eq."+OPERATION, "required": "eq.true", "active": "eq.true", "select": "step_id"})
    step_contracts = read("lf_operation_step_contracts", {"operation_code": "eq."+OPERATION,"status":"eq.ACTIVE_ENFORCEMENT","select":"step_id"})
    judges = read("lf_operation_judges", {"operation_code": "eq."+OPERATION,"status":"eq.ACTIVE_ENFORCEMENT","select":"judge_code"})
    bindings = read("lf_operation_step_judge_bindings", {"operation_code": "eq."+OPERATION,"status":"eq.ACTIVE_ENFORCEMENT","select":"step_id"})
    # Informational R17 discovery only; presence does not establish attestation.
    r17 = read("lf_eventos", {"evento_tipo": "eq.RUNTIME_PREFLIGHT", "select": "id,entidad_codigo",
                               "order": "id.desc", "limit": "30"})
    executions = read("lf_operation_execution", {"operation_code": "eq."+OPERATION,
        "target_type": "eq."+TARGET_TYPE, "target_code": "eq."+target,
        "status": "eq.IN_PROGRESS", "select": "execution_id,target_code"})

    blockers: list[str] = []
    if len(registry) != 1 or registry[0].get("lifecycle_state_code") != "OP_OPERATIONAL" or registry[0].get("status") not in ("ACTIVE","OPERATIVA","ACTIVO"):
        blockers.append("OPERATION_NOT_OPERATIONAL")
    if len(route) != 1 or route[0].get("write_allowed") is not True or route[0].get("status") != "ACTIVE":
        blockers.append("ROUTE_WRITE_NOT_AUTHORIZED")
    if len(contract) != 1 or not isinstance(contract[0].get("allowed"),dict) or contract[0]["allowed"].get("runtime_effect_enabled") is not True:
        blockers.append("RUNTIME_EFFECT_DISABLED")
    if (len(steps) != 8 or {x.get("step_id") for x in steps} != STEP_IDS
        or len(step_contracts) != 8 or {x.get("step_id") for x in step_contracts} != STEP_IDS
        or len(judges) != 8 or len({x.get("judge_code") for x in judges}) != 8
        or len(bindings) != 8 or {x.get("step_id") for x in bindings} != STEP_IDS):
        blockers.append("STEP_AUTHORITY_BINDINGS_INCOMPLETE")
    if not r17:
        blockers.append("R17_CANONICAL_EVENT_MISSING")
    else:
        blockers.append("R17_CANONICAL_ATTESTATION_UNVERIFIED")
    if len(executions) != 1:
        blockers.append("EXACT_OPERATION_EXECUTION_MISSING")
    # This read-only adapter cannot certify a signed authority receipt or effect lease.
    blockers += ["SIGNED_RUNTIME_AUTHORITY_UNVERIFIED", "EFFECT_RESERVATION_UNVERIFIED",
                 "EDGE_MANAGEMENT_CREDENTIAL_UNVERIFIED"]

    return {
        "schema_version": "LF_EDGE_OPERATION_AUTHORITY_DIAGNOSTIC_V1",
        "operation_code": OPERATION, "target": target,
        "mode": "READ_ONLY_NO_RUNTIME_EFFECT",
        "step_count": len(steps), "step_contract_count":len(step_contracts),
        "judge_count":len(judges), "binding_count":len(bindings),
        "r17_event_count":len(r17),
        "blockers": blockers,
        "can_deploy": False, "effect_executed": False,
    }


def main() -> int:
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("--target", required=True)
    args = p.parse_args()
    try:
        reader = build_live_reader(
            os.environ.get("LF_SUPABASE_OPERATION_URL",""),
            os.environ.get("LF_SUPABASE_OPERATION_READ_TOKEN",""),
        )
        result = diagnose(reader, args.target)
    except AuthorityUnavailable as exc:
        result = {"schema_version": "LF_EDGE_OPERATION_AUTHORITY_DIAGNOSTIC_V1",
                  "mode":"READ_ONLY_NO_RUNTIME_EFFECT", "can_deploy":False,
                  "effect_executed":False, "blockers":[str(exc)]}
    print(json.dumps(result,sort_keys=True))
    return 0 if not result["blockers"] else 2


if __name__=="__main__":
    sys.exit(main())
