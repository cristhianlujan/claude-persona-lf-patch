#!/usr/bin/env python3
"""Authorize one specific owner Issue #3907 event for LF IG transport guard deployment.
Read-only preflight: no Github API, no network, no secrets. Fail-closed.
"""
import json
import os
import re
import sys
from pathlib import Path
ISSUE=3907
OWNER="cristhianlujan"
REPO="cristhianlujan/claude-persona-lf-patch"
PROJECT="mhwmirqcgxxukpctffuv"
COMMIT="337b863711166136063b7e3878c7f3d98af13596"
ROLLBACK="d25d3350346620d23a61de277cac796b3be6a8c3"
EXPECTED={
 "schema_version":"LF_IG_TRANSPORT_EDGE_DEPLOY_REQUEST_V1",
 "project_ref":PROJECT,
 "source_min_merge_commit":COMMIT,
 "rollback_source_commit":ROLLBACK,
 "functions":{"input-governance-agent-v1":19,
              "input-governance-validator-v1":20,
              "input-governance-curator-v1":15},
 "verify_jwt":True,
 "environment":"lf-edge-deploy",
}
class Blocked(Exception):
    pass

def validate(event:dict,env:dict)->dict:
    if (env.get("GITHUB_EVENT_NAME")!="issue_comment"
        or env.get("GITHUB_REF")!="refs/heads/main"
        or env.get("GITHUB_REPOSITORY")!=REPO
        or not re.fullmatch("[a-f0-9]{40}",env.get("GITHUB_SHA",""))):
        raise Blocked("IG_DEPLOY_GITHUB_CONTEXT_INVALID")
    issue=event.get("issue",{})
    comment=event.get("comment",{})
    if (event.get("action")!="created" or issue.get("number")!=ISSUE
        or issue.get("state")!="open" or issue.get("pull_request") is not None
        or comment.get("body")!="LF_IG_TRANSPORT_DEPLOY_EXECUTE_V1"
        or comment.get("author_association")!="OWNER"
        or (comment.get("user") or {}).get("login")!=OWNER):
        raise Blocked("IG_DEPLOY_OWNER_ISSUE_AUTHORITY_INVALID")
    try:body=json.loads(issue.get("body",""))
    except (TypeError,ValueError):raise Blocked("IG_DEPLOY_ISSUE_BODY_NOT_JSON")
    if body!=EXPECTED:raise Blocked("IG_DEPLOY_ISSUE_BODY_SCOPE_DRIFT")
    return {"status":"AUTHORITY_PASS","issue":ISSUE,"project":PROJECT,
        "functions":sorted(EXPECTED["functions"]),"source_min_commit":COMMIT,
        "rollback_commit":ROLLBACK,"verify_jwt":True}

def main()->int:
    try:
        event=json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text(encoding="utf-8"))
        print(json.dumps(validate(event,os.environ),sort_keys=True))
        return 0
    except (Blocked,KeyError,FileNotFoundError,ValueError) as e:
        print(json.dumps({"status":"BLOCKED","code":str(e)}))
        return 2

if __name__=="__main__":sys.exit(main())
