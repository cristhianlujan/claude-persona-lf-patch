#!/usr/bin/env python3
"""Synthetic HTTP tests for PR93 E.16 authenticated Actions inventory."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.dont_write_bytecode = True
HEAD = "a" * 40


def run_item(name: str, event: str, ident: int, *, status: str = "completed", conclusion: str | None = "success", head: str = HEAD, number: int | None = None) -> dict[str, object]:
    return {
        "id": ident,
        "name": name,
        "event": event,
        "head_sha": head,
        "head_branch": "lf/e16-test",
        "status": status,
        "conclusion": conclusion,
        "run_number": number or ident,
        "run_attempt": 1,
        "created_at": "2026-08-04T20:00:00Z",
        "updated_at": "2026-08-04T20:01:00Z",
        "html_url": f"https://example.invalid/runs/{ident}",
    }


POSITIVE = [
    run_item("lf-contract-check", "push", 101),
    run_item("lf-contract-check", "pull_request", 102, status="in_progress", conclusion=None),
    run_item("Validate LF Packs", "push", 103),
    run_item("Validate LF Packs", "pull_request", 104),
]


REQUEST_COUNTS: dict[str, int] = {}


class Handler(BaseHTTPRequestHandler):
    server_version = "E16Synthetic/1"

    def log_message(self, format: str, *args: object) -> None:
        return

    def do_GET(self) -> None:
        scenario = self.path.split("/", 2)[1]
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
        page = int(query.get("page", ["1"])[0])
        if self.headers.get("Authorization") != "Bearer synthetic-token":
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b'{"message":"bad token"}')
            return
        if scenario == "malformed":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"not-json")
            return
        if scenario == "loop":
            payload = {"total_count": len(POSITIVE), "workflow_runs": POSITIVE}
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Link", f"<http://127.0.0.1:{self.server.server_port}/loop/repos/o/r/actions/runs?head_sha={HEAD}&per_page=100&page=1>; rel=\"next\"")
            self.end_headers()
            self.wfile.write(json.dumps(payload).encode())
            return
        if scenario == "eventual":
            REQUEST_COUNTS[scenario] = REQUEST_COUNTS.get(scenario, 0) + 1
            items = POSITIVE[:-1] if REQUEST_COUNTS[scenario] == 1 else POSITIVE
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"total_count": len(items), "workflow_runs": items}).encode())
            return
        if scenario == "positive":
            items = POSITIVE[:2] if page == 1 else POSITIVE[2:]
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            if page == 1:
                self.send_header("Link", f"<http://127.0.0.1:{self.server.server_port}/positive/repos/o/r/actions/runs?head_sha={HEAD}&per_page=100&page=2>; rel=\"next\"")
            self.end_headers()
            self.wfile.write(json.dumps({"total_count": len(POSITIVE), "workflow_runs": items}).encode())
            return
        if scenario == "crossorigin":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Link", f"<http://example.invalid/repos/o/r/actions/runs?head_sha={HEAD}&per_page=100&page=2>; rel=\"next\"")
            self.end_headers()
            self.wfile.write(json.dumps({"total_count": len(POSITIVE), "workflow_runs": POSITIVE}).encode())
            return
        if scenario == "countmismatch":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"total_count": len(POSITIVE) + 1, "workflow_runs": POSITIVE}).encode())
            return
        if scenario == "missing":
            items = POSITIVE[:-1]
        elif scenario == "failed":
            items = POSITIVE + [run_item("Validate LF Packs", "push", 999, conclusion="failure", number=999)]
        elif scenario == "wronghead":
            items = [dict(item, head_sha="b" * 40) for item in POSITIVE]
        else:
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"total_count": len(items), "workflow_runs": items}).encode())


def invoke(script: Path, base: str, output: Path, *, token: str | None = "synthetic-token", wait: float = 0.0) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.pop("GITHUB_TOKEN", None)
    if token is not None:
        env["GITHUB_TOKEN"] = token
    return subprocess.run(
        [
            sys.executable,
            str(script),
            "--repository", "o/r",
            "--head-sha", HEAD,
            "--output", str(output),
            "--api-base", base,
            "--matrix-wait-seconds", str(wait),
            "--poll-interval-seconds", "0.01",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
        text=True,
        env=env,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--inventory", type=Path, required=True)
    args = parser.parse_args()

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix="pr93-e16-inventory-") as temp:
            root = Path(temp)
            port = server.server_port
            cases = [
                ("positive", 0, "PASS_E16_CANONICAL_ACTIONS_INVENTORY=4/4"),
                ("eventual", 0, "PASS_E16_CANONICAL_ACTIONS_INVENTORY=4/4"),
                ("missing", 2, "FAIL_E16_ACTIONS_MATRIX_INCOMPLETE"),
                ("failed", 2, "FAIL_E16_ACTIONS_RUN_FAILED"),
                ("wronghead", 2, "FAIL_E16_ACTIONS_API_FILTER_MISMATCH"),
                ("malformed", 2, "FAIL_E16_ACTIONS_API_JSON"),
                ("loop", 2, "FAIL_E16_ACTIONS_API_PAGINATION"),
                ("crossorigin", 2, "FAIL_E16_ACTIONS_API_PAGINATION"),
                ("countmismatch", 2, "FAIL_E16_ACTIONS_API_PAGINATION"),
            ]
            passed = 0
            for index, (scenario, expected_exit, marker) in enumerate(cases, start=1):
                result = invoke(
                    args.inventory.resolve(),
                    f"http://127.0.0.1:{port}/{scenario}",
                    root / f"{scenario}.json",
                    wait=1.0 if scenario == "eventual" else 0.0,
                )
                if result.returncode != expected_exit or marker not in result.stdout:
                    raise SystemExit(
                        f"{scenario}: exit={result.returncode} expected={expected_exit}; output={result.stdout}"
                    )
                if scenario in {"positive", "eventual"}:
                    record = json.loads((root / f"{scenario}.json").read_text(encoding="utf-8"))
                    if record.get("matrix_complete") is not True:
                        raise SystemExit("positive record is not complete")
                    expected_pages = 2 if scenario == "positive" else 1
                    if record.get("api", {}).get("pages_fetched") != expected_pages:
                        raise SystemExit("pagination was not recorded")
                    if record.get("declaration_kind") != "MEASURED_AUTHENTICATED_API":
                        raise SystemExit("measurement kind is incorrect")
                    if len(record.get("all_matching_runs", [])) != 4:
                        raise SystemExit("full run inventory was not persisted")
                    if record.get("selected_pending_present") is not True or record.get("selected_pending_count") != 1:
                        raise SystemExit("pending-state observability is missing")
                    if record.get("selected_latest_known_failure_present") is not False:
                        raise SystemExit("latest failure marker is incorrect")
                    if scenario == "eventual" and record.get("api", {}).get("poll_attempts", 0) < 2:
                        raise SystemExit("eventual consistency was not retried")
                passed += 1
                print(f"PASS_E16_CA_N93_{index:02d}={scenario}")

            token_result = invoke(
                args.inventory.resolve(),
                f"http://127.0.0.1:{port}/positive",
                root / "token.json",
                token=None,
            )
            if token_result.returncode != 2 or "FAIL_E16_GITHUB_TOKEN_MISSING" not in token_result.stdout:
                raise SystemExit(f"missing-token case failed: {token_result.stdout}")
            passed += 1
            print(f"PASS_E16_CA_N93_{passed:02d}=missing-token")

            if passed != 10:
                raise SystemExit(f"CA-N93 test count mismatch: {passed}")
            print("PASS_E16_CA_N93_INVENTORY_TESTS=10/10")
            return 0
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


if __name__ == "__main__":
    raise SystemExit(main())
