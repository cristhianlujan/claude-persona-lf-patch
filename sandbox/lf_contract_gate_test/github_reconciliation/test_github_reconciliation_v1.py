#!/usr/bin/env python3
from __future__ import annotations

from github_reconciliation_v1 import evaluate_github_reconciliation, scope_digest

SHA = "a" * 40
P1 = "sandbox/a.txt"
P2 = "governance/anchor.json"


def req():
    return {
        "orchestrator_execution_id": "ORCH-1",
        "consumer_execution_id": "POST-1",
        "capability_code": "GITHUB_RECONCILIATION",
        "plan_digest": "p" * 64,
        "dispatch_receipt_id": "D-1",
        "request_digest": "r" * 64,
        "source_revision": SHA,
        "entry_guard_readback": {"decision": "ORCHESTRATOR_ENTRY_ACCEPTED"},
    }


def scoped():
    s = {
        "schema_version": "LF_GITHUB_RECONCILIATION_SCOPE_V1",
        "repository": "cristhianlujan/claude-persona-lf-patch",
        "target_branch": "main",
        "plan_digest": "p" * 64,
        "expected_merge_commit_sha": SHA,
        "declared_paths": [
            {"path": P1, "kind": "CHANGED", "expected_sha256": "1" * 64, "expected_git_blob": "1" * 40},
            {"path": P2, "kind": "ANCHOR", "expected_sha256": "2" * 64, "expected_git_blob": "2" * 40},
        ],
        "repository_invariants": ["MAIN_PROTECTED", "MERGE_PR_BOUND"],
    }
    s["scope_digest"] = scope_digest(s)
    return s


def obs():
    return {
        "source_workflow": {"event": "push", "head_branch": "main", "head_sha": SHA, "status": "completed", "conclusion": "success"},
        "pull_request": {"number": 1337, "state": "MERGED", "merged": True, "merge_commit_sha": SHA},
        "branch_readback": {"branch": "main", "head_sha": SHA},
        "files": [
            {"path": P1, "sha256": "1" * 64, "git_blob": "1" * 40, "commit_sha": SHA},
            {"path": P2, "sha256": "2" * 64, "git_blob": "2" * 40, "commit_sha": SHA},
        ],
        "repository_invariants": {"MAIN_PROTECTED": True, "MERGE_PR_BOUND": True},
    }


def main():
    checks = 0
    r = evaluate_github_reconciliation(request=req(), scope=scoped(), observation=obs())
    assert r["decision"] == "RECONCILED" and r["ready"] is True and r["declared_path_count"] == 2
    checks += 1

    q = req(); q["entry_guard_readback"] = {"decision": "BLOCK"}
    r = evaluate_github_reconciliation(request=q, scope=scoped(), observation=obs())
    assert r["reason"] == "ORCHESTRATOR_ENTRY_REQUIRED"
    checks += 1

    s = scoped(); s["declared_paths"].append({"path": P1, "kind": "ANCHOR", "expected_sha256": "1"*64, "expected_git_blob": "1"*40}); s["scope_digest"] = scope_digest(s)
    r = evaluate_github_reconciliation(request=req(), scope=s, observation=obs())
    assert r["reason"] == "DECLARED_PATH_DUPLICATE"
    checks += 1

    o = obs(); o["files"].append({"path": "unrelated.txt", "sha256": "3"*64, "git_blob": "3"*40, "commit_sha": SHA})
    r = evaluate_github_reconciliation(request=req(), scope=scoped(), observation=o)
    assert any(x["reason"] == "UNDECLARED_FILE_EVIDENCE" for x in r["failures"])
    checks += 1

    o = obs(); o["files"][0]["sha256"] = "f"*64
    r = evaluate_github_reconciliation(request=req(), scope=scoped(), observation=o)
    assert any(x["reason"] == "FILE_SHA256_MISMATCH" for x in r["failures"])
    checks += 1

    o = obs(); o["source_workflow"]["conclusion"] = "failure"
    r = evaluate_github_reconciliation(request=req(), scope=scoped(), observation=o)
    assert any(x["reason"] == "SOURCE_WORKFLOW_MISMATCH" for x in r["failures"])
    checks += 1

    o = obs(); o["pull_request"]["merge_commit_sha"] = "b"*40
    r = evaluate_github_reconciliation(request=req(), scope=scoped(), observation=o)
    assert any(x["reason"] == "MERGED_PR_MISMATCH" for x in r["failures"])
    checks += 1

    o = obs(); o["branch_readback"]["head_sha"] = "b"*40
    r = evaluate_github_reconciliation(request=req(), scope=scoped(), observation=o)
    assert any(x["reason"] == "MAIN_HEAD_MISMATCH" for x in r["failures"])
    checks += 1

    o = obs(); o["repository_invariants"]["MAIN_PROTECTED"] = False
    r = evaluate_github_reconciliation(request=req(), scope=scoped(), observation=o)
    assert any(x["reason"] == "REPOSITORY_INVARIANT_FAILED" for x in r["failures"])
    checks += 1

    s = scoped(); s["scope_digest"] = "0"*64
    r = evaluate_github_reconciliation(request=req(), scope=s, observation=obs())
    assert r["reason"] == "SCOPE_DIGEST_MISMATCH"
    checks += 1

    q = req(); q["source_revision"] = "b"*40
    r = evaluate_github_reconciliation(request=q, scope=scoped(), observation=obs())
    assert r["reason"] == "REQUEST_SOURCE_REVISION_MISMATCH"
    checks += 1

    s = scoped(); s["declared_paths"] = [s["declared_paths"][0]]; s["repository_invariants"] = []; s["scope_digest"] = scope_digest(s)
    o = obs(); o["files"] = [o["files"][0]]; o["repository_invariants"] = {}
    r = evaluate_github_reconciliation(request=req(), scope=s, observation=o)
    assert r["decision"] == "RECONCILED" and r["declared_path_count"] == 1
    checks += 1

    print(f"PASS_GITHUB_RECONCILIATION_V1 checks={checks}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
