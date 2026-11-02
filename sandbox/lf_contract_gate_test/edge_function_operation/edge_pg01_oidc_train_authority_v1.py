#!/usr/bin/env python3
"""Candidate read-only admission of independently issued LF Merge Train evidence.

Not an authorization to deploy on its own. Requires separate credential/issuer
provenance review before being wired to deployment.
"""
from __future__ import annotations
from datetime import datetime, timezone

def parse_time(value):
    if not isinstance(value,str):
        return None
    try:
        result=datetime.fromisoformat(value.replace("Z","+00:00"))
        return result if result.tzinfo is not None else None
    except ValueError:
        return None


TARGET_REPO = "cristhianlujan/claude-persona-lf-patch"
TARGET_SLUG = "lf-pg01-oidc-authority-v1"
TARGET_PATHS = frozenset({
    "supabase/functions/lf-pg01-oidc-authority-v1/index.ts",
    "supabase/functions/lf-pg01-oidc-authority-v1/auth.ts",
})


def qualify_deploy_binding(main: str, slug: str, checked_out_sha: str, source_paths: object) -> str | None:
    """Fail-closed binding of a candidate to the exact deployment target.

    This is not a replay-protected permit or an operational deploy authorization.
    """
    if slug != TARGET_SLUG:
        return "DEPLOY_TARGET_MISMATCH"
    if checked_out_sha != main:
        return "DEPLOY_CHECKOUT_SHA_MISMATCH"
    if not isinstance(source_paths, list) or any(not isinstance(p, str) for p in source_paths):
        return "DEPLOY_SOURCE_PATHS_INVALID"
    if set(source_paths) != TARGET_PATHS or len(source_paths) != len(TARGET_PATHS):
        return "DEPLOY_SOURCE_PATHS_MISMATCH"
    return None


def qualify(main: str, pr: object, status: object, run: object) -> str | None:
    if not isinstance(main, str) or len(main) != 40 or any(c not in "0123456789abcdef" for c in main):
        return "MAIN_SHA_INVALID"
    if not isinstance(pr, dict) or pr.get("merged_at") is None or pr.get("state") != "closed":
        return "PR_NOT_MERGED"
    if not isinstance(pr.get("base"), dict) or pr["base"].get("ref") != "main" or pr.get("merge_commit_sha") != main:
        return "MERGE_SHA_NOT_CURRENT_MAIN"
    source = pr.get("head", {}).get("sha") if isinstance(pr.get("head"), dict) else None
    if not isinstance(source, str) or len(source) != 40:
        return "PR_SOURCE_SHA_INVALID"
    if not isinstance(status, dict) or status.get("sha") != source:
        return "STATUS_HEAD_MISMATCH"
    statuses = status.get("statuses")
    if not isinstance(statuses, list):
        return "TRAIN_STATUSES_INVALID"
    relevant = [s for s in statuses if isinstance(s, dict) and s.get("context") == "lf-merge-train/verified"]
    candidates = [s for s in relevant if s.get("state") == "success"]
    # No competing historical status can be used as an alternate approval.
    if len(relevant) != 1:
        return "TRAIN_STATUS_AMBIGUOUS_OR_MISSING"
    if len(candidates) != 1:
        return "INDEPENDENT_TRAIN_STATUS_MISSING_OR_AMBIGUOUS"
    st = candidates[0]
    creator = st.get("creator")
    if not isinstance(creator, dict) or creator.get("type") != "Bot" or creator.get("login") != "lf-migration-train[bot]" or creator.get("id") != 338337340:
        return "STATUS_NOT_TRUSTED_TRAIN_APP"
    if not isinstance(run, dict) or run.get("conclusion") != "success" or run.get("status") != "completed":
        return "TRAIN_RUN_NOT_SUCCESS"
    if run.get("path") != ".github/workflows/lf-migration-merge-train.yml":
        return "TRAIN_WORKFLOW_MISMATCH"
    if run.get("event") != "pull_request_target":
        return "TRAIN_EVENT_MISMATCH"
    if not isinstance(run.get("repository"),dict) or run["repository"].get("full_name") != "cristhianlujan/claude-persona-lf-patch":
        return "TRAIN_REPO_MISMATCH"
    # On pull_request_target the successful workflow run is bound to the PR
    # source SHA, not the resulting merge commit on main.
    if run.get("head_sha") != source:
        return "TRAIN_SOURCE_HEAD_MISMATCH"
    if run.get("workflow_id") != 375839198 or type(run.get("id")) is not int or run["id"] <= 0:
        return "TRAIN_WORKFLOW_ID_MISMATCH"
    started = parse_time(run.get("run_started_at"))
    stamped = parse_time(st.get("created_at"))
    merged = parse_time(pr.get("merged_at"))
    if started is None or stamped is None or merged is None:
        return "TRAIN_PROVENANCE_TIME_MISSING"
    if not (started <= stamped <= merged):
        return "TRAIN_PROVENANCE_TIME_ORDER_MISMATCH"
    return None
