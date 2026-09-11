#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hmac
import json
import os
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

EXECUTION_RE = re.compile(r"^EXEC-[A-Z0-9][A-Z0-9_-]{7,172}$")
STEP_RE = re.compile(r"^[a-z0-9_]{2,80}$")
OPERATIONS = {"CREACION_PERFIL_LF", "ACTUALIZACION_PERFIL_LF"}
PSQL_CONTAINER = os.environ.get("S26_PSQL_CONTAINER", "s26-profile-pg")
RUNTIME_URL = os.environ.get("S26_LOCAL_RUNTIME_URL", "http://127.0.0.1:18082").rstrip("/")
LOCAL_KEY = os.environ.get("LOCAL_SERVICE_ROLE_KEY", "")


def sql_lit(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def require_execution(value: str) -> str:
    if not EXECUTION_RE.fullmatch(value):
        raise ValueError("EXECUTION_ID_INVALID")
    return value


def require_step(value: str) -> str:
    if not STEP_RE.fullmatch(value):
        raise ValueError("STEP_ID_INVALID")
    return value


def require_operation(value: str) -> str:
    if value not in OPERATIONS:
        raise ValueError("OPERATION_CODE_INVALID")
    return value


def eq_param(params: dict[str, list[str]], name: str, *, required: bool = True) -> str:
    raw = (params.get(name) or [""])[0]
    if raw.startswith("eq."):
        return raw[3:]
    if required:
        raise ValueError(f"FILTER_{name.upper()}_INVALID")
    return ""


def psql(sql: str) -> str:
    completed = subprocess.run(
        ["docker", "exec", PSQL_CONTAINER, "psql", "-X", "-v", "ON_ERROR_STOP=1", "-Atq", "-c", sql],
        text=True,
        capture_output=True,
        check=False,
        timeout=30,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout).strip().replace("\n", " | ")[:1200]
        raise RuntimeError(f"PSQL_FAILED:{completed.returncode}:{detail}")
    return completed.stdout.strip()


def array_sql(inner: str) -> str:
    return f"select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb)::text from ({inner}) q"


def get_sql(path: str, params: dict[str, list[str]]) -> str:
    if path == "/rest/v1/lf_operation_execution":
        execution_id = require_execution(eq_param(params, "execution_id"))
        return array_sql(
            "select execution_id,operation_code,target_type,target_code,target_repo,target_path,status,manifest,updated_at "
            f"from public.lf_operation_execution where execution_id={sql_lit(execution_id)} limit 1"
        )
    if path == "/rest/v1/lf_operation_execution_steps":
        execution_id = require_execution(eq_param(params, "execution_id"))
        extra = ""
        step_order = eq_param(params, "step_order", required=False)
        step_id = eq_param(params, "step_id", required=False)
        if step_order:
            if not step_order.isdigit():
                raise ValueError("STEP_ORDER_INVALID")
            extra += f" and step_order={int(step_order)}"
        if step_id:
            extra += f" and step_id={sql_lit(require_step(step_id))}"
        return array_sql(
            "select execution_id,step_order,step_id,status,evidence_ref,evidence_payload,observed_at "
            f"from public.lf_operation_execution_steps where execution_id={sql_lit(execution_id)}{extra} order by step_order asc"
        )
    if path == "/rest/v1/lf_operation_steps":
        op = require_operation(eq_param(params, "operation_code"))
        return array_sql(
            "select step_order,execution_order,step_id,required,evidence_required "
            f"from public.lf_operation_steps where operation_code={sql_lit(op)} and active=true order by execution_order asc"
        )
    if path == "/rest/v1/lf_operation_step_contracts":
        op = require_operation(eq_param(params, "operation_code"))
        return array_sql(
            "select step_id,step_order,execution_order,status,resolver_ref,required_evidence_keys,next_if_pass,next_if_blocked,blocking_code "
            f"from public.lf_operation_step_contracts where operation_code={sql_lit(op)} order by execution_order asc"
        )
    if path == "/rest/v1/lf_operation_step_judge_bindings":
        op = require_operation(eq_param(params, "operation_code"))
        return array_sql(
            "select step_id,step_order,judge_code,clean_result_value,blocked_result_value,return_result_value,required_evidence_keys "
            f"from public.lf_operation_step_judge_bindings where operation_code={sql_lit(op)} and status='ACTIVE_ENFORCEMENT' order by step_order asc"
        )
    if path == "/rest/v1/v_lf_operation_policy_snapshot":
        op = require_operation(eq_param(params, "operation_code"))
        return array_sql(
            f"select * from public.v_lf_operation_policy_snapshot where operation_code={sql_lit(op)}"
        )
    raise ValueError("REST_PATH_NOT_ALLOWED")


def rpc_sql(name: str, body: dict[str, Any]) -> str:
    if name not in {"lf_record_profile_operation_step_v1", "lf_record_creacion_perfil_step_v1"}:
        raise ValueError("RPC_NOT_ALLOWED")
    execution_id = require_execution(str(body.get("p_execution_id", "")))
    actor = require_execution(str(body.get("p_actor_execution_id", "")))
    step_id = require_step(str(body.get("p_step_id", "")))
    evidence_ref = str(body.get("p_evidence_ref", "")).strip()
    evidence = body.get("p_evidence_payload")
    if not evidence_ref or not isinstance(evidence, dict):
        raise ValueError("RPC_EVIDENCE_INVALID")
    payload = json.dumps(evidence, ensure_ascii=False, separators=(",", ":"))
    return (
        f"select public.{name}("
        f"{sql_lit(execution_id)},{sql_lit(step_id)},{sql_lit(evidence_ref)},{sql_lit(payload)}::jsonb,{sql_lit(actor)}"
        ")::text"
    )


def authorized(headers: Any) -> bool:
    if not LOCAL_KEY:
        return False
    bearer = headers.get("authorization", "")
    apikey = headers.get("apikey", "")
    expected = f"Bearer {LOCAL_KEY}"
    return hmac.compare_digest(bearer, expected) or hmac.compare_digest(apikey, LOCAL_KEY)


class Handler(BaseHTTPRequestHandler):
    server_version = "lf-profile-local-pooler-bridge/1"

    def log_message(self, fmt: str, *args: Any) -> None:
        print("BRIDGE", fmt % args, flush=True)

    def respond(self, status: int, payload: Any) -> None:
        raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", "application/json; charset=utf-8")
        self.send_header("content-length", str(len(raw)))
        self.send_header("cache-control", "no-store")
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        if parsed.path == "/health":
            self.respond(200, {"status": "PASS", "bridge": "POSTGRES_POOLER_DIRECT", "write": False})
            return
        if not authorized(self.headers):
            self.respond(403, {"code": "LOCAL_BRIDGE_AUTH_REQUIRED"})
            return
        try:
            sql = get_sql(parsed.path, urllib.parse.parse_qs(parsed.query, keep_blank_values=True))
            raw = psql(sql)
            self.respond(200, json.loads(raw or "[]"))
        except ValueError as exc:
            self.respond(400, {"code": str(exc)})
        except Exception as exc:
            self.respond(500, {"code": str(exc)[:1200]})

    def do_POST(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        if not authorized(self.headers):
            self.respond(403, {"code": "LOCAL_BRIDGE_AUTH_REQUIRED"})
            return
        length = int(self.headers.get("content-length", "0") or "0")
        body_raw = self.rfile.read(length)
        if parsed.path == "/functions/v1/run-creacion-perfil-lf":
            try:
                req = urllib.request.Request(
                    RUNTIME_URL,
                    data=body_raw,
                    method="POST",
                    headers={"authorization": self.headers.get("authorization", ""), "content-type": "application/json"},
                )
                try:
                    with urllib.request.urlopen(req, timeout=125) as response:
                        payload = response.read()
                        status = response.status
                except urllib.error.HTTPError as exc:
                    payload = exc.read()
                    status = exc.code
                self.send_response(status)
                self.send_header("content-type", "application/json; charset=utf-8")
                self.send_header("content-length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            except Exception as exc:
                self.respond(502, {"code": f"LOCAL_RUNTIME_PROXY_FAILED:{str(exc)[:1000]}"})
            return
        prefix = "/rest/v1/rpc/"
        if parsed.path.startswith(prefix):
            try:
                body = json.loads(body_raw.decode("utf-8") or "{}")
                if not isinstance(body, dict):
                    raise ValueError("RPC_BODY_INVALID")
                sql = rpc_sql(parsed.path[len(prefix):], body)
                raw = psql(sql)
                self.respond(200, json.loads(raw or "null"))
            except ValueError as exc:
                self.respond(400, {"code": str(exc)})
            except Exception as exc:
                self.respond(500, {"code": str(exc)[:1200]})
            return
        self.respond(404, {"code": "POST_PATH_NOT_ALLOWED"})


def self_test() -> None:
    q = {"execution_id": ["eq.EXEC-ACTUALIZACION-PERFIL-TEST-0001"]}
    assert "lf_operation_execution" in get_sql("/rest/v1/lf_operation_execution", q)
    q2 = {"operation_code": ["eq.ACTUALIZACION_PERFIL_LF"]}
    assert "active=true" in get_sql("/rest/v1/lf_operation_steps", q2)
    sql = rpc_sql(
        "lf_record_profile_operation_step_v1",
        {
            "p_execution_id": "EXEC-ACTUALIZACION-PERFIL-TEST-0001",
            "p_step_id": "pre_write_execution_binding_gate",
            "p_evidence_ref": "self-test",
            "p_evidence_payload": {"step_result": "STEP_PASS_WITH_EVIDENCE", "blocking_codes": []},
            "p_actor_execution_id": "EXEC-ACTUALIZACION-PERFIL-TEST-0001",
        },
    )
    assert "lf_record_profile_operation_step_v1" in sql
    for bad_path in ("/rest/v1/unknown", "/rest/v1/rpc/unknown"):
        try:
            if "/rpc/" in bad_path:
                rpc_sql("unknown", {})
            else:
                get_sql(bad_path, {})
        except ValueError:
            pass
        else:
            raise AssertionError(f"FAIL_OPEN:{bad_path}")
    print("PASS_PROFILE_CREATOR_LOCAL_POOLER_BRIDGE_SELFTEST=5/5")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if not LOCAL_KEY:
        raise SystemExit("LOCAL_SERVICE_ROLE_KEY_REQUIRED")
    server = ThreadingHTTPServer((args.bind, args.port), Handler)
    print(json.dumps({"status": "READY", "bind": args.bind, "port": args.port, "runtime_url": RUNTIME_URL}), flush=True)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
