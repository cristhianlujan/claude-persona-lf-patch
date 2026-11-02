#!/usr/bin/env python3
"""Candidate read-only admission of independently issued LF Merge Train evidence.

Not an authorization to deploy on its own. Requires separate credential/issuer
provenance review before being wired to deployment.
"""
from __future__ import annotations

def qualify(main: str, pr: object, status: object, run: object) -> str | None:
    if not isinstance(main, str) or len(main) != 40 or any(c not in "0123456789abcdef" for c in main):
        return "MAIN_SHA_INVALID"
    if not isinstance(pr, dict) or pr.get("merged_at") is None or pr.get("state") != "closed":
        return "PR_NOT_MERGED"
    if pr.get("base", {}).get("ref") != "main" or pr.get("merge_commit_sha") != main:
        return "MERGE_SHA_NOT_CURRENT_MAIN"
    source = pr.get("head", {}).get("sha")
    if not isinstance(source, str) or len(source) != 40:
        return "PR_SOURCE_SHA_INVALID"
    if not isinstance(status, dict) or status.get("sha") != source:
        return "STATUS_HEAD_MISMATCH"
    candidates = [s for s in status.get("statuses", []) if isinstance(s, dict) and s.get("context") == "lf-merge-train/verified" and s.get("state") == "success"]
    if len(candidates) != 1:
        return "INDEPENDENT_TRAIN_STATUS_MISSING_OR_AMBIGUOUS"
    st = candidates[0]
    creator = st.get("creator", {})
    if not isinstance(creator, dict) or creator.get("type") != "Bot" or creator.get("login") != "lf-migration-train[bot]" or creator.get("id") != 338337340:
        return "STATUS_NOT_TRUSTED_TRAIN_APP"
    if not isinstance(run, dict) or run.get("conclusion") != "success" or run.get("status") != "completed":
        return "TRAIN_RUN_NOT_SUCCESS"
    if run.get("path") != ".github/workflows/lf-migration-merge-train.yml":
        return "TRAIN_WORKFLOW_MISMATCH"
    if run.get("event") != "pull_request_target":
        return "TRAIN_EVENT_MISMATCH"
    if run.get("repository", {}).get("full_name") != "cristhianlujan/claude-persona-lf-patch":
        return "TRAIN_REPO_MISMATCH"
    # On pull_request_target the successful workflow run is bound to the PR
    # source SHA, not the resulting merge commit on main.
    if run.get("head_sha") != source:
        return "TRAIN_SOURCE_HEAD_MISMATCH"
    return None
