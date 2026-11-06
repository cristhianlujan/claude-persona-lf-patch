"""PG-07 -> PG-08 real *unauthenticated sandbox evidence* adapter.

Every byte exposed to PG-08..PG-14 is checked against a separately pinned
fixture SHA-256. It never claims authenticated execution, never dispatches a
Worker, and never modifies existing PG-07..PG-14 candidate producers.
"""
from __future__ import annotations

import base64
import binascii
from decimal import Decimal, InvalidOperation
import hashlib
import json
from pathlib import Path
import re
from typing import Any

COMMIT = "e76b213cb2f367f787e0eba3bf8ff74136edd883"
TREE = "922f74a8ffaab9b8233625c804b8c92a17d8b8a3"
SUBTREE = "4ba97b68310e913795d7ae1ac35d5912e2fe6551"
BASE = "28de535acd4a76be038013cc6241c59a08102155"
PATCH_SHA = "bfba0329bcac92dbde06a1319a16acd535acd718f224df6121dae3c70fe307c6"
RUN_ID = 42284754122
KIND = "REAL_SANDBOX_UNAUTHENTICATED"
FILE_COUNT = 18
FILE_BYTES = 29347
MAX_USD = Decimal("0.35")
WARN_USD = Decimal("0.28")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
HUNK_RE = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
SOURCE_PREFIX = "apps/time-service/"
REQUIREMENTS = {"REM-C" + str(i) for i in range(1, 8)}
ALL_AUTHORITY = ("production_authority", "tool_execution_verified",
                 "receipt_authenticated", "pg12_admitted", "write_allowed",
                 "handoff_allowed", "dispatch_allowed", "worker_invoked")
CONTROL_FLAGS = ("production_authority", "tool_execution_verified", "receipt_authenticated")
SMOKE = (("time", 200), ("post", 201), ("search", 200),
         ("delete", 204), ("not_found", 404))


class EvidenceBlocked(ValueError):
    pass


def fail(code: str):
    raise EvidenceBlocked(code)


def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def git_oid(kind: str, raw: bytes) -> str:
    return hashlib.sha1(kind.encode("ascii") + b" " +
                        str(len(raw)).encode("ascii") + b"\0" + raw).hexdigest()


def blob64(value: Any, where: str) -> bytes:
    if not isinstance(value, str):
        fail("BLOCK_BASE64_" + where)
    try:
        raw = base64.b64decode(value, validate=True)
    except (ValueError, binascii.Error):
        fail("BLOCK_BASE64_" + where)
    if base64.b64encode(raw).decode("ascii") != value:
        fail("BLOCK_NONCANONICAL_BASE64_" + where)
    return raw


def check_raw(data: dict, key: str, where: str) -> bytes:
    raw = blob64(data.get(key + "_base64"), where)
    if data.get(key + "_sha256") != sha256(raw):
        fail("BLOCK_DIGEST_" + where)
    if data.get(key + "_bytes") != len(raw):
        fail("BLOCK_LENGTH_" + where)
    return raw


def ensure_authority_false(payload: Any):
    if isinstance(payload, dict):
        for name, value in payload.items():
            if name in ALL_AUTHORITY and value is not False:
                fail("BLOCK_AUTHORITY_INJECTED")
            ensure_authority_false(value)
    elif isinstance(payload, list):
        for value in payload:
            ensure_authority_false(value)


def subtree_oid(files: list[dict]) -> str:
    """Canonical Git tree encoding from *all* tracked files, no git executable."""
    root: dict[str, Any] = {}
    for f in files:
        path = f.get("path")
        if not isinstance(path, str) or not path.startswith(SOURCE_PREFIX):
            fail("BLOCK_FILE_SCOPE")
        suffix = path.removeprefix(SOURCE_PREFIX)
        if (not suffix or "\\" in suffix or
            any(part in ("", ".", "..") for part in suffix.split("/"))):
            fail("BLOCK_PATH_TRAVERSAL")
        components = suffix.split("/")
        node = root
        for name in components[:-1]:
            if name not in node:
                node[name] = {}
            if not isinstance(node[name], dict):
                fail("BLOCK_FILE_TREE_COLLISION")
            node = node[name]
        leaf = components[-1]
        if leaf in node or f.get("mode") != "100644":
            fail("BLOCK_DUPLICATE_OR_UNSAFE_MODE")
        raw = blob64(f.get("content_base64"), "FILE")
        if len(raw) != f.get("bytes"):
            fail("BLOCK_FILE_SIZE")
        oid = git_oid("blob", raw)
        if oid != f.get("oid"):
            fail("BLOCK_BLOB_OID")
        node[leaf] = oid

    def encode(node: dict[str, Any]) -> str:
        elements: list[tuple[str, bytes]] = []
        for name, value in node.items():
            is_dir = isinstance(value, dict)
            oid = encode(value) if is_dir else value
            entry = ("40000" if is_dir else "100644").encode("ascii") + b" " + \
                    name.encode("utf-8") + b"\0" + bytes.fromhex(oid)
            elements.append((name + ("/" if is_dir else ""), entry))
        tree = b"".join(chunk for _, chunk in sorted(elements, key=lambda p: p[0].encode("utf-8")))
        return git_oid("tree", tree)
    return encode(root)


def verify_hunks(patch: bytes, rows: Any) -> list[dict]:
    if not isinstance(rows, list) or len(rows) != 6:
        fail("BLOCK_HUNK_COUNT")
    lines = patch.decode("utf-8").splitlines(keepends=True)
    found: list[tuple[str, bytes, tuple[int, int, int, int]]] = []
    current_path = None
    collected: list[str] = []
    def flush():
        nonlocal collected
        if not collected:
            return
        m = HUNK_RE.match(collected[0])
        if not m or not current_path:
            fail("BLOCK_HUNK_HEADER")
        coords = tuple(int(m.group(i) or 1) for i in range(1, 5))
        found.append((current_path, "".join(collected).encode("utf-8"), coords))
        collected = []
    for line in lines:
        if line.startswith("diff --git "):
            flush()
            m = re.match(r"diff --git a/(.+) b/(.+)\n?$", line)
            if not m or m.group(1) != m.group(2):
                fail("BLOCK_PATCH_FILE")
            current_path = m.group(2)
        elif line.startswith("@@ "):
            flush()
            collected = [line]
        elif collected:
            collected.append(line)
    flush()
    if len(found) != len(rows):
        fail("BLOCK_HUNK_SET")
    seen: set[str] = set()
    coverage: set[str] = set()
    for (path, raw, coords), row in zip(found, rows):
        expected = {
            "path": path, "old_start": coords[0], "old_count": coords[1],
            "new_start": coords[2], "new_count": coords[3],
            "sha256": sha256(raw),
        }
        if not isinstance(row, dict) or any(row.get(k) != v for k, v in expected.items()):
            fail("BLOCK_HUNK_INTEGRITY")
        if blob64(row.get("text_base64"), "HUNK") != raw:
            fail("BLOCK_HUNK_BYTES")
        reqs = row.get("requirements")
        if not isinstance(reqs, list) or not reqs or any(r not in REQUIREMENTS for r in reqs):
            fail("BLOCK_HUNK_REQUIREMENT_MISSING")
        key = path + ":" + str(coords[0]) + ":" + str(coords[2])
        if key in seen:
            fail("BLOCK_HUNK_DUPLICATE")
        seen.add(key)
        coverage.update(reqs)
    if coverage != REQUIREMENTS:
        fail("BLOCK_REQUIREMENT_WITHOUT_HUNK")
    return rows


def cost_decision(raw: bytes, ceiling: Decimal = MAX_USD) -> dict:
    try:
        cost = json.loads(raw)
        value = Decimal(str(cost["total_estimated_usd"]))
    except (TypeError, ValueError, KeyError, InvalidOperation):
        fail("BLOCK_COST_FORMAT")
    if not value.is_finite() or value < 0 or ceiling != MAX_USD:
        fail("BLOCK_COST_POLICY")
    if value > ceiling:
        fail("BLOCK_COST_EXCEEDED")
    if value == ceiling:
        return {"verdict": "REQUIRES_DECISION", "reported_cost_usd": str(value),
                "authenticated": False}
    if value >= WARN_USD:
        return {"verdict": "WARN", "reported_cost_usd": str(value),
                "authenticated": False}
    return {"verdict": "REPORTED_WITHIN_BUDGET_UNVERIFIED",
            "reported_cost_usd": str(value), "authenticated": False}


def load_bundle(path: Path, expected_sha256: str) -> dict:
    if not isinstance(expected_sha256, str) or not SHA_RE.fullmatch(expected_sha256):
        fail("BLOCK_PIN_REQUIRED")
    raw = path.read_bytes()
    if sha256(raw) != expected_sha256:
        fail("BLOCK_BUNDLE_SHA")
    try:
        b = json.loads(raw)
    except (ValueError, UnicodeError):
        fail("BLOCK_JSON")
    if not isinstance(b, dict) or b.get("schema_version") != "LF_EX5C_EVIDENCE_BUNDLE_V1":
        fail("BLOCK_SCHEMA")
    if b.get("evidence_kind") != KIND:
        fail("BLOCK_EVIDENCE_KIND")
    ensure_authority_false(b)
    if any(b.get(k) is not False for k in CONTROL_FLAGS):
        fail("BLOCK_AUTHORITY_INJECTED")
    git = b.get("git")
    if not isinstance(git, dict):
        fail("BLOCK_GIT")
    if (git.get("commit"), git.get("tree"), git.get("subtree_oid"),
        git.get("base_commit"), git.get("base_subtree_oid")) != (
        COMMIT, TREE, SUBTREE, BASE, "91ac08b61d4fbb20d47dacc698778def71f2c805"):
        fail("BLOCK_GIT_IDENTITY")
    raw_commit = blob64(git.get("raw_commit_base64"), "COMMIT")
    if git_oid("commit", raw_commit) != COMMIT:
        fail("BLOCK_COMMIT_OID")
    commit_lines = raw_commit.split(b"\n\n", 1)[0].split(b"\n")
    if b"tree " + TREE.encode() not in commit_lines:
        fail("BLOCK_COMMIT_TREE")
    parents = [line.decode("ascii").split(" ", 1)[1] for line in commit_lines
               if line.startswith(b"parent ")]
    if git.get("parents") != parents or len(parents) != 2:
        fail("BLOCK_COMMIT_PARENTS")
    files = b.get("files")
    if (not isinstance(files, list) or len(files) != FILE_COUNT or
        b.get("file_count") != FILE_COUNT or
        sum(row.get("bytes", -1) for row in files if isinstance(row, dict)) != FILE_BYTES or
        b.get("file_bytes") != FILE_BYTES):
        fail("BLOCK_FILE_COUNT")
    if subtree_oid(files) != SUBTREE:
        fail("BLOCK_SUBTREE_OID")
    patch = b.get("patch")
    if not isinstance(patch, dict):
        fail("BLOCK_PATCH")
    diff = blob64(patch.get("text_base64"), "PATCH")
    if (sha256(diff) != PATCH_SHA or patch.get("sha256") != PATCH_SHA or
        patch.get("worker_patch_sha256") != PATCH_SHA):
        fail("BLOCK_PATCH_SHA")
    verify_hunks(diff, patch.get("hunks"))
    worker = b.get("worker")
    if not isinstance(worker, dict) or worker.get("run_id") != RUN_ID:
        fail("BLOCK_RUN_ID")
    if worker.get("model_resolved") != "claude-sonnet-5-5":
        fail("BLOCK_MODEL")
    receipts = worker.get("receipts")
    names = ("verified-worker-receipt.json", "visible-worker-receipt.json",
             "cost.json", "derived-context.json")
    if not isinstance(receipts, dict) or set(receipts) != set(names):
        fail("BLOCK_RECEIPTS")
    decoded = {}
    for name in names:
        value = receipts[name]
        if not isinstance(value, dict):
            fail("BLOCK_RECEIPT_SHAPE")
        payload = {"content_base64": value.get("content_base64"),
                   "content_sha256": value.get("sha256"),
                   "content_bytes": value.get("bytes")}
        decoded[name] = check_raw(payload, "content", name)
    verified = json.loads(decoded["verified-worker-receipt.json"])
    visible = json.loads(decoded["visible-worker-receipt.json"])
    derived = json.loads(decoded["derived-context.json"])
    if (verified.get("status") != "PASS" or verified.get("visible_status") != "PASS" or
        verified.get("task_id") != "LF-WORKER-PILOT-REAL-005C" or
        visible.get("status") != "PASS" or
        verified.get("resolved_model") != worker["model_resolved"]):
        fail("BLOCK_WORKER_RECEIPT_LINK")
    if derived.get("sha256") != "9cc719ef41a3b9e70d21b94780e0b17a6887fb57b4683eeaaf3157c2a1cb676d":
        fail("BLOCK_CONTEXT_SHA")
    # The derivation receipt hashes the canonical record excluding its own SHA.
    context_unhashed = {k: v for k, v in derived.items() if k != "sha256"}
    context_bytes = (json.dumps(context_unhashed, sort_keys=True, ensure_ascii=False,
                                separators=(",", ":")) + "\n").encode("utf-8")
    if sha256(context_bytes) != derived.get("sha256"):
        fail("BLOCK_CONTEXT_INTERNAL_SHA")
    cost_object = json.loads(decoded["cost.json"])
    pricing_row = worker.get("pricing")
    if not isinstance(pricing_row, dict):
        fail("BLOCK_PRICING_MISSING")
    pricing_raw = check_raw(
        {"content_base64": pricing_row.get("content_base64"),
         "content_sha256": pricing_row.get("sha256"),
         "content_bytes": pricing_row.get("bytes")}, "content", "PRICING")
    if sha256(pricing_raw) != cost_object.get("price_table_sha256"):
        fail("BLOCK_PRICING_LINK")
    pricing = json.loads(pricing_raw)
    if (pricing.get("version") != cost_object.get("price_table_version") or
        pricing.get("currency") != "USD" or
        pricing.get("price_unit") != "per_1_000_000_tokens" or
        cost_object.get("real_api_usage") is not True or
        cost_object.get("model") != worker.get("model_resolved") or
        cost_object.get("receipt_sha256") != visible.get("receipt_sha256") or
        verified.get("visible_receipt_sha256") != visible.get("receipt_sha256") or
        verified.get("source_snapshot_sha256") != visible.get("source_snapshot_sha256")):
        fail("BLOCK_COST_OR_RECEIPT_LINK")
    price = pricing["models"][worker["model_resolved"]]
    try:
        inputs = cost_object["total_input_tokens"]
        outputs = cost_object["total_output_tokens"]
        if (type(inputs) is not int or type(outputs) is not int or
            inputs < 0 or outputs < 0 or
            inputs != sum(a["input_tokens"] for a in cost_object["attempts"]) or
            outputs != sum(a["output_tokens"] for a in cost_object["attempts"])):
            fail("BLOCK_COST_USAGE_COUNTER")
        measured = (Decimal(inputs) * Decimal(price["input_usd_per_million"]) +
                    Decimal(outputs) * Decimal(price["output_usd_per_million"])) / Decimal(1000000)
        if measured != Decimal(cost_object["total_estimated_usd"]):
            fail("BLOCK_COST_RECALCULATION")
    except (KeyError, TypeError, ValueError, InvalidOperation):
        fail("BLOCK_COST_RECALCULATION")
    execution = b.get("execution")
    if not isinstance(execution, dict):
        fail("BLOCK_EXECUTION")
    build = execution.get("maven_verify")
    if not isinstance(build, dict):
        fail("BLOCK_MAVEN_RECEIPT")
    argv = ["mvn", "-B", "-f", "apps/time-service/pom.xml", "verify"]
    if build.get("argv") != argv or build.get("exit_code") != 0:
        fail("BLOCK_MAVEN_EXIT_OR_COMMAND")
    check_raw(build, "stdout", "MAVEN_STDOUT")
    check_raw(build, "stderr", "MAVEN_STDERR")
    if type(build.get("duration_ns")) is not int or build["duration_ns"] < 0:
        fail("BLOCK_MAVEN_DURATION")
    smoke = execution.get("smoke")
    if not isinstance(smoke, dict) or not isinstance(smoke.get("steps"), list):
        fail("BLOCK_SMOKE")
    check_raw(smoke, "server_stdout", "JAR_STDOUT")
    check_raw(smoke, "server_stderr", "JAR_STDERR")
    if len(smoke["steps"]) != len(SMOKE):
        fail("BLOCK_SMOKE_COUNT")
    for item, (name, status) in zip(smoke["steps"], SMOKE):
        if item.get("name") != name or item.get("status") != status:
            fail("BLOCK_SMOKE_STATUS")
        raw_body = blob64(item.get("body_base64"), "SMOKE_BODY")
        if len(raw_body) != item.get("body_bytes") or sha256(raw_body) != item.get("body_sha256"):
            fail("BLOCK_SMOKE_BODY")
    b["_derived"] = {
        "bundle_sha256": expected_sha256, "maven_result": "REPORTED_PASS_UNVERIFIED",
        "smoke_healthcheck": "REPORTED_PASS_UNVERIFIED",
        "cost_decision": cost_decision(decoded["cost.json"]),
        "git_subtree_verified_from_bytes": True,
        "raw_commit_oid_verified_from_bytes": True,
        "worker_reference_only": True,
    }
    return b


def pg08_c1_observation(b: dict, solution_id: str,
                        config_sha256: str) -> list[dict]:
    """One observation for existing PG-08 C1 producer; no authority elevation."""
    if not SHA_RE.fullmatch(config_sha256):
        fail("BLOCK_BUILD_CONFIG_DIGEST")
    build = b["execution"]["maven_verify"]
    return [{
        "solution_id": solution_id,
        "executor_mode": "WORKER_API",
        "executor_result_ref": f"sandbox-run:{RUN_ID}",
        "candidate_head_sha": COMMIT,
        "diff_sha256": PATCH_SHA,
        "target_repo": "paulozterra/lf-programming-sandbox",
        "base_head_sha": BASE,
        "commands": [{
            "command_id": "ex5c-maven-verify", "command_ref": "mvn -B -f apps/time-service/pom.xml verify",
            "tool_name": "maven", "tool_version": "reported-not-authenticated",
            "config_sha256": config_sha256,
            "execution_receipt_ref": "bundle:" + b["_derived"]["bundle_sha256"],
            "stdout_sha256": build["stdout_sha256"],
            "stderr_sha256": build["stderr_sha256"],
            "result": "PASS", "exit_code": 0,
        }],
    }]


def worker_reference(b: dict) -> dict:
    receipts = b["worker"]["receipts"]
    return {
        "evidence_kind": KIND,
        "run_id": RUN_ID, "resolved_model": "claude-sonnet-5-5",
        "receipt_sha256": {name: row["sha256"] for name, row in receipts.items()},
        "worker_invoked": False, "production_authority": False,
        "tool_execution_verified": False, "receipt_authenticated": False,
    }


def independent_review_binding(author: str, reviewer: str) -> dict:
    """Identity *declarations* only, not proof of an actual independent review."""
    if not isinstance(author, str) or not isinstance(reviewer, str):
        fail("BLOCK_REVIEW_IDENTITY")
    if author == reviewer:
        fail("SELF_REVIEW")
    if author != "worker:claude-sonnet-5-5" or reviewer != "reviewer:claude-opus-verifier":
        fail("BLOCK_REVIEW_IDENTITY")
    return {"author_reported": author, "reviewer_reported": reviewer,
            "review_attested": False, "production_authority": False}


def pg09_cost_reference(b: dict) -> dict:
    """Reported billing reference for existing PG-09 cost governor."""
    data = b["_derived"]["cost_decision"]
    return {"source_run": RUN_ID, "model": "claude-sonnet-5-5",
            "max_cost_usd": str(MAX_USD), "reported_cost_usd": data["reported_cost_usd"],
            "verdict": data["verdict"], "receipt_authenticated": False,
            "usage_authenticated": False, "production_authority": False}
