#!/usr/bin/env python3
"""Synthetic HTTP tests for E.16 exact-current-carrier Actions readback."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HEAD = "a" * 40
RUN_ID = 101


def run_item(
    *,
    ident: int = RUN_ID,
    name: str = "lf-contract-check",
    event: str = "pull_request",
    head: str = HEAD,
    status: str = "in_progress",
    conclusion: str | None = None,
) -> dict[str, object]:
    return {
        "id": ident,
        "name": name,
        "event": event,
        "head_sha": head,
        "head_branch": "lf/e16-test",
        "status": status,
        "conclusion": conclusion,
        "run_number": 77,
        "run_attempt": 1,
        "created_at": "2026-09-18T15:00:00Z",
        "updated_at": "2026-09-18T15:01:00Z",
        "html_url": f"https://example.invalid/runs/{ident}",
        "workflow_id": 55,
        "path": ".github/workflows/lf-contract-check.yml",
    }


SCENARIOS = {
    "positive": run_item(),
    "completed": run_item(status="completed", conclusion="success"),
    "wronghead": run_item(head="b" * 40),
    "wrongworkflow": run_item(name="Validate LF Packs"),
    "wrongevent": run_item(event="push"),
    "wrongid": run_item(ident=999),
    "failed": run_item(status="completed", conclusion="failure"),
    "completednone": run_item(status="completed", conclusion=None),
    "badstatus": run_item(status="mystery"),
}


class Handler(BaseHTTPRequestHandler):
    server_version = "E16Synthetic/2"

    def log_message(self, format: str, *args: object) -> None:
        return

    def do_GET(self) -> None:
        parts = self.path.split("/")
        scenario = parts[1] if len(parts) > 1 else ""
        if self.headers.get("Authorization") != "Bearer synthetic-token":
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b'{"message":"bad token"}')
            return
        if scenario == "http500":
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b'{"message":"boom"}')
            return
        if scenario == "malformed":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"not-json")
            return
        payload = SCENARIOS.get(scenario)
        if payload is None:
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(payload).encode())


def run_case(inventory: Path, root: Path, base: str, scenario: str, expected_rc: int, marker: str) -> None:
    out = root / f"{scenario}.json"
    env = os.environ.copy()
    env.update(
        {
            "GITHUB_TOKEN": "synthetic-token",
            "GITHUB_RUN_ID": str(RUN_ID),
            "GITHUB_WORKFLOW": "lf-contract-check",
            "GITHUB_EVENT_NAME": "pull_request",
        }
    )
    result = subprocess.run(
        [
            sys.executable,
            str(inventory),
            "--repository",
            "o/r",
            "--head-sha",
            HEAD,
            "--output",
            str(out),
            "--api-base",
            f"{base}/{scenario}",
        ],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    if result.returncode != expected_rc or marker not in result.stdout:
        raise SystemExit(
            f"{scenario}: expected rc={expected_rc} marker={marker!r}; "
            f"got rc={result.returncode}\n{result.stdout}"
        )
    if expected_rc == 0:
        record = json.loads(out.read_text(encoding="utf-8"))
        if record.get("carrier_scope") != "CURRENT_CARRIER_ONLY":
            raise SystemExit(f"{scenario}: wrong carrier scope")
        if record.get("cross_carrier_wait_required") is not False:
            raise SystemExit(f"{scenario}: cross-carrier wait unexpectedly enabled")
        if record.get("current_run", {}).get("id") != RUN_ID:
            raise SystemExit(f"{scenario}: wrong current run")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--inventory", type=Path, required=True)
    args = parser.parse_args()
    inventory = args.inventory.resolve()

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix="pr93-e16-inventory-") as temp:
            root = Path(temp)
            base = f"http://127.0.0.1:{server.server_port}"
            cases = [
                ("positive", 0, "PASS_E16_CURRENT_CARRIER_ACTIONS_READBACK=1/1"),
                ("completed", 0, "PASS_E16_CURRENT_CARRIER_ACTIONS_READBACK=1/1"),
                ("wronghead", 2, "FAIL_E16_ACTIONS_HEAD_MISMATCH"),
                ("wrongworkflow", 2, "FAIL_E16_ACTIONS_WORKFLOW_MISMATCH"),
                ("wrongevent", 2, "FAIL_E16_ACTIONS_EVENT_MISMATCH"),
                ("wrongid", 2, "FAIL_E16_ACTIONS_RUN_ID_MISMATCH"),
                ("failed", 2, "FAIL_E16_ACTIONS_RUN_FAILED"),
                ("completednone", 2, "FAIL_E16_ACTIONS_RUN_NOT_SUCCESS"),
                ("badstatus", 2, "FAIL_E16_ACTIONS_RUN_STATUS_INVALID"),
                ("malformed", 2, "FAIL_E16_ACTIONS_API_JSON"),
                ("http500", 2, "FAIL_E16_ACTIONS_API_HTTP"),
            ]
            for scenario, rc, marker in cases:
                run_case(inventory, root, base, scenario, rc, marker)

            out = root / "token-missing.json"
            env = os.environ.copy()
            env.update(
                {
                    "GITHUB_RUN_ID": str(RUN_ID),
                    "GITHUB_WORKFLOW": "lf-contract-check",
                    "GITHUB_EVENT_NAME": "pull_request",
                }
            )
            env.pop("GITHUB_TOKEN", None)
            result = subprocess.run(
                [
                    sys.executable,
                    str(inventory),
                    "--repository",
                    "o/r",
                    "--head-sha",
                    HEAD,
                    "--output",
                    str(out),
                    "--api-base",
                    f"{base}/positive",
                ],
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
            )
            if result.returncode != 2 or "FAIL_E16_GITHUB_TOKEN_MISSING" not in result.stdout:
                raise SystemExit("missing-token negative failed")

            existing = root / "exists.json"
            existing.write_text("{}\n", encoding="utf-8")
            env = os.environ.copy()
            env.update(
                {
                    "GITHUB_TOKEN": "synthetic-token",
                    "GITHUB_RUN_ID": str(RUN_ID),
                    "GITHUB_WORKFLOW": "lf-contract-check",
                    "GITHUB_EVENT_NAME": "pull_request",
                }
            )
            result = subprocess.run(
                [
                    sys.executable,
                    str(inventory),
                    "--repository",
                    "o/r",
                    "--head-sha",
                    HEAD,
                    "--output",
                    str(existing),
                    "--api-base",
                    f"{base}/positive",
                ],
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
            )
            if result.returncode != 2 or "FAIL_E16_ACTIONS_INVENTORY_EXISTS" not in result.stdout:
                raise SystemExit("existing-output negative failed")
    finally:
        server.shutdown()
        server.server_close()

    print("PASS_E16_ACTIONS_READBACK_TESTS=13/13")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
