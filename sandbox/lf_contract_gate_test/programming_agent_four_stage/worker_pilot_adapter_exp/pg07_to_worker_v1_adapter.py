#!/usr/bin/env python3
"""Strict PG07 V2 -> WorkerTaskSpec V1 pilot adapter (NO MODEL, NO SECRETS).

Source authority: programming-agent @298307e2f9cac72abfde2b181f3554b0e28bad24
(see worker_spec.py and worker_cli.py). All manifests are owner-provided and
copied only to a private directory outside the repository. No fake oracle/QA.
"""
from __future__ import annotations
import hashlib
import json
import os
import re
import shlex
from pathlib import Path
from typing import Any

WORKER_COMMIT="298307e2f9cac72abfde2b181f3554b0e28bad24"
TASK_FIELDS=frozenset({
 "schema_version","task_id","objective","base_head_sha","source_snapshot_sha256",
 "context_path_patterns","write_path_patterns","protected_path_patterns","acceptance_commands",
 "max_attempts","max_patch_bytes","max_changed_files","max_context_bytes","allow_deletions"})
PG07_REQUIRED=frozenset({
 "schema_version","task_id","objective","expected_change","human_story","functional_contract",
 "scope","cases","dependency_resolution","dependency_task_ids","required_tests","required_evidence",
 "blocked_if","base_head_sha","source_snapshot_sha256","context_path_patterns",
 "write_path_patterns","protected_path_patterns","files_expected","platform_refs",
 "interface_refs","acceptance_commands","max_attempts","max_patch_bytes","max_changed_files",
 "max_context_bytes","allow_deletions"})
LIMITS={"max_attempts":1,"max_context_bytes":60000,"max_patch_bytes":20000,
        "max_changed_files":3,"max_output_tokens":8000}
OBJ_MAX_BYTES=18000
_SHA40=re.compile(r"^[a-f0-9]{40}$")
_SHA64=re.compile(r"^[a-f0-9]{64}$")
_NAME=re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
FORBIDDEN_ARG_CHARS=set("|;&<>\\\n\\r`$*?{}[]()")
class AdapterBlocked(ValueError):
    pass
def fail(code):raise AdapterBlocked(code)
def canonical(v):
    return json.dumps(v,sort_keys=True,separators=(",",":"),ensure_ascii=False,allow_nan=False).encode("utf-8")
def sha(v):return hashlib.sha256(canonical(v)).hexdigest()
def sha_bytes(v):return hashlib.sha256(v).hexdigest()
def exact(x,fields,code):
    if not isinstance(x,dict) or set(x)!=set(fields):fail(code)
def safe_name(x):
    return isinstance(x,str) and bool(_NAME.fullmatch(x))
def check_limits(spec):
    for field,cap in LIMITS.items():
        if field=="max_output_tokens":continue
        x=spec.get(field)
        if type(x) is not int or x<1 or x>cap:fail("PILOT_LIMIT_MISSING_OR_EXCEEDED:"+field)
    if spec.get("allow_deletions") is not False:fail("PILOT_DELETIONS_FORBIDDEN")
def commands_from_declared(raw):
    """Never interpret shell; each user-declared command becomes an argv array."""
    if not isinstance(raw,list) or not raw or len(raw)>32:fail("ACCEPTANCE_MISSING")
    result=[]
    seen=set()
    for index,c in enumerate(raw):
        if isinstance(c,str):
            if not c.strip() or any(ch in c for ch in FORBIDDEN_ARG_CHARS):
                fail("ACCEPTANCE_SHELL_OR_AMBIGUOUS")
            try:argv=shlex.split(c,posix=True)
            except ValueError:fail("ACCEPTANCE_PARSE_INVALID")
            if not argv:fail("ACCEPTANCE_MISSING")
            # No commands are fabricated: owner must supply timeout/output limits
            # separately when PG07 has legacy string commands.
            fail("ACCEPTANCE_COMMAND_METADATA_MISSING")
        exact(c,{"name","argv","timeout_seconds","max_output_bytes"},"ACCEPTANCE_COMMAND_FORMAT_INVALID")
        if not safe_name(c["name"]) or c["name"] in seen:fail("ACCEPTANCE_COMMAND_NAME_INVALID")
        if not isinstance(c["argv"],list) or not 1<=len(c["argv"])<=64:fail("ACCEPTANCE_ARGV_INVALID")
        for item in c["argv"]:
            if (not isinstance(item,str) or not item or
                any(ch in item for ch in FORBIDDEN_ARG_CHARS) or
                len(item.encode("utf-8"))>4096):
                fail("ACCEPTANCE_SHELL_OR_AMBIGUOUS")
        if (type(c["timeout_seconds"]) is not int or not 1<=c["timeout_seconds"]<=900 or
            type(c["max_output_bytes"]) is not int or not 1024<=c["max_output_bytes"]<=2000000):
            fail("ACCEPTANCE_LIMIT_INVALID")
        seen.add(c["name"]);result.append(c.copy())
    return result
def bind_declared_commands(raw,owner_metadata):
    """Associate owner-provided execution metadata to an EXACT original string;
    no invented argv, timeout, or shell interpretation. Dictionary commands may
    be passed straight through. The metadata is also independently reviewed."""
    if isinstance(raw,list) and all(isinstance(x,dict) for x in raw):
        return commands_from_declared(raw)
    if not isinstance(raw,list) or not raw:fail("ACCEPTANCE_MISSING")
    if not isinstance(owner_metadata,list) or len(owner_metadata)!=len(raw):
        fail("ACCEPTANCE_COMMAND_METADATA_MISSING")
    out=[]
    for text,meta in zip(raw,owner_metadata):
        if not isinstance(text,str) or not text.strip() or any(ch in text for ch in FORBIDDEN_ARG_CHARS):
            fail("ACCEPTANCE_SHELL_OR_AMBIGUOUS")
        try:argv=shlex.split(text,posix=True)
        except ValueError:fail("ACCEPTANCE_PARSE_INVALID")
        if not argv:fail("ACCEPTANCE_MISSING")
        exact(meta,{"source_command","name","argv","timeout_seconds","max_output_bytes"},
              "ACCEPTANCE_METADATA_FIELDS_INVALID")
        if meta["source_command"]!=text or meta["argv"]!=argv:
            fail("ACCEPTANCE_OWNER_ARGV_NOT_EXACT")
        out.append({k:meta[k] for k in ("name","argv","timeout_seconds","max_output_bytes")})
    return commands_from_declared(out)
def _safe_paths(x):
    if not isinstance(x,list) or not x or len(set(x))!=len(x) or not all(isinstance(p,str) for p in x):
        fail("SCOPE_INVALID")
    for p in x:
        if (p.startswith("/") or "\\" in p or ".." in p.split("/") or
            ".git" in p.split("/") or not p.strip()):
            fail("SCOPE_INVALID")
    return x
def _role_stack(pg07):
    fc=pg07["functional_contract"]
    if not isinstance(fc,dict) or not isinstance(fc.get("role_and_stack"),dict):
        fail("ROLE_STACK_MISSING")
    rs=fc["role_and_stack"]
    if not isinstance(rs.get("profile_sha256"),str) or not _SHA64.fullmatch(rs["profile_sha256"]):
        fail("ROLE_SHA_MISSING")
    text=rs.get("profile_rules")
    if not isinstance(text,str) or sha_bytes(text.encode("utf-8"))!=rs["profile_sha256"]:
        fail("ROLE_SHA_DRIFT")
    skills=rs.get("skills")
    if not isinstance(skills,list) or not skills:fail("SKILL_SET_MISSING")
    if not isinstance(rs.get("skill_set_sha256"),str) or not _SHA64.fullmatch(rs["skill_set_sha256"]):
        fail("SKILL_SET_SHA_MISSING")
    identities=[];blocks=[];priority=[]
    for item in skills:
        if not isinstance(item,dict):fail("SKILL_INVALID")
        for k in ("skill_code","skill_version","skill_sha256","skill_rules","priority","expert_rules"):
            if k not in item:fail("SKILL_INCOMPLETE")
        if (type(item["priority"]) is not int or item["priority"]<=0 or
            not isinstance(item["skill_sha256"],str) or not _SHA64.fullmatch(item["skill_sha256"]) or
            not isinstance(item["skill_rules"],str) or
            sha_bytes(item["skill_rules"].encode("utf-8"))!=item["skill_sha256"]):
            fail("SKILL_SHA_OR_PRIORITY_INVALID")
        priority.append(item["priority"])
        identities.append({k:item[k] for k in ("skill_code","skill_version","skill_sha256","priority")})
        rules=item["expert_rules"]
        if not isinstance(rules,list) or len(rules)<3 or len({r.get("rule_id") for r in rules})<3:
            fail("SKILL_RULES_TOO_FEW")
        blocks.append((item,rules))
    if len(set(priority))!=len(priority) or priority!=sorted(priority):fail("SKILL_PRIORITY_CONFLICT")
    if sha(identities)!=rs["skill_set_sha256"]:fail("SKILL_SET_SHA_DRIFT")
    if rs.get("profile_code") is None:fail("PROFILE_CODE_MISSING")
    return rs,blocks
def objective_with_rules(pg07):
    rs,blocks=_role_stack(pg07)
    origin=pg07["objective"]
    if not isinstance(origin,str) or not origin.strip():fail("OBJECTIVE_MISSING")
    chunks=[origin,"[LF ROLE SOURCE]","profile_code="+str(rs["profile_code"]),
            "profile_sha256="+rs["profile_sha256"],
            "role_rules_begin",rs["profile_rules"],"role_rules_end"]
    for item,rules in blocks:
        chunks+=["[LF SKILL SOURCE]","skill_code="+str(item["skill_code"]),
                 "skill_version="+str(item["skill_version"]),
                 "skill_sha256="+item["skill_sha256"],
                 "skill_set_sha256="+rs["skill_set_sha256"]]
        for rule in rules:
            if (not isinstance(rule,dict) or set(rule)!={"rule_id","text","source_url"} or
                not all(isinstance(rule[k],str) and rule[k].strip() for k in rule) or
                not rule["source_url"].startswith("https://") or
                "**"+rule["rule_id"]+":** "+rule["text"] not in item["skill_rules"] or
                rule["source_url"] not in item["skill_rules"]):
                fail("SKILL_RULE_NOT_SOURCE_BOUND")
            chunks.append("RULE "+rule["rule_id"]+" | "+rule["text"]+" | SOURCE "+rule["source_url"])
    goal="\n".join(chunks)
    if len(goal.encode("utf-8"))>OBJ_MAX_BYTES:fail("OBJECTIVE_RULES_TOO_LARGE")
    if "oracle_envelope" in goal or "hidden_oracle" in goal or "holdout.oracle" in goal:
        fail("ORACLE_IN_OBJECTIVE")
    return goal
def adapt(pg07,*,owner_commands=None,pg07_overlay=None):
    """Output Worker V1 plus separate sealed envelope. Never grant dispatch."""
    if not isinstance(pg07,dict) or not PG07_REQUIRED.issubset(pg07):
        fail("PG07_TASK_INCOMPLETE")
    if pg07.get("schema_version")!=2:fail("PG07_SCHEMA_INVALID")
    check_limits(pg07)
    if pg07_overlay is None or not isinstance(pg07_overlay,dict):
        fail("PG07_SOURCE_OVERLAY_REQUIRED")
    if (pg07_overlay.get("production_authority") is not False or
        pg07_overlay.get("dispatch_allowed") is not False or
        pg07_overlay.get("worker_invoked") is not False or
        pg07_overlay.get("worker_task_overlay",{}).get("worker_spec_sha256")!=sha(pg07)):
        fail("PG07_OVERLAY_NOT_BOUND")
    write=_safe_paths(pg07["write_path_patterns"])
    if sorted(write)!=sorted(pg07_overlay["worker_task_overlay"].get("write_scope",[])):
        fail("WRITE_SCOPE_MISMATCH")
    if not isinstance(pg07["context_path_patterns"],list) or not isinstance(pg07["protected_path_patterns"],list):
        fail("PATHS_INVALID")
    if not pg07["protected_path_patterns"]:fail("PROTECTED_SCOPE_EMPTY")
    task={k:pg07[k] for k in TASK_FIELDS if k not in ("schema_version","objective","acceptance_commands")}
    task.update(schema_version=1,objective=objective_with_rules(pg07),
                acceptance_commands=bind_declared_commands(pg07["acceptance_commands"],owner_commands))
    exact(task,TASK_FIELDS,"WORKER_V1_FIELDS_INVALID")
    check_limits(task)
    if not _SHA40.fullmatch(task["base_head_sha"]) or not _SHA64.fullmatch(task["source_snapshot_sha256"]):
        fail("SOURCE_IDENTITY_INVALID")
    envelope={"schema_version":"LF_WORKER_V1_EXTRA_ENVELOPE_V1","task_id":task["task_id"],
              "task_sha256":sha(task),"pg07_sha256":sha(pg07),
              "pg07_extra":{k:pg07[k] for k in sorted(set(pg07)-TASK_FIELDS)},
              "pg07_worker_task_overlay":pg07_overlay["worker_task_overlay"],
              "production_authority":False}
    envelope["envelope_sha256"]=sha(envelope)
    return task,envelope

def _write_private(path:Path,document):
    data=canonical(document)+b"\n"
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    try:
        with os.fdopen(fd,"wb") as handle:handle.write(data)
    except BaseException:
        path.unlink(missing_ok=True);raise
    return sha_bytes(data)
def materialize_external(*,repo_root:Path,outside_dir:Path,task,envelope,
                         owner_quality_plan,owner_readback_manifest,owner_hidden_oracle,
                         validate_quality,validate_readback,validate_oracle):
    """Fail closed: do not fabricate QA classifications, oracle tests or readback sources.
    The owner MUST supply real valid manifests; adapter exports private exact copies."""
    repository=repo_root.resolve(strict=True)
    output=outside_dir.resolve()
    if output==repository or output.is_relative_to(repository):fail("EXTERNAL_FILES_INSIDE_REPO")
    if output.exists():fail("OUTPUT_DIRECTORY_MUST_NOT_EXIST")
    for obj in (owner_quality_plan,owner_readback_manifest,owner_hidden_oracle):
        if not isinstance(obj,dict):fail("OWNER_MANIFEST_MISSING")
        if obj.get("task_id",task["task_id"])!=task["task_id"]:fail("MANIFEST_TASK_ID_MISMATCH")
    # Validators here are original Worker functions pinned to 298307e.
    validate_quality(owner_quality_plan)
    validate_readback(owner_readback_manifest)
    validate_oracle(owner_hidden_oracle)
    output.mkdir(mode=0o700,parents=False)
    names=[("task.v1.json",task),("extra.envelope.json",envelope),
           ("quality-plan.json",owner_quality_plan),("readback-manifest.json",owner_readback_manifest),
           ("holdout.oracle.json",owner_hidden_oracle)]
    digests={name:_write_private(output/name,obj) for name,obj in names}
    return {"directory":str(output),"sha256":digests}
def build_worker_command(*,repo_path:Path,output_dir:Path,model="claude-haiku-5-5",provider="anthropic"):
    if provider!="anthropic" or model not in ("claude-haiku-5-5","claude-sonnet-5-5"):
        fail("PILOT_PROVIDER_OR_MODEL_FORBIDDEN")
    q=output_dir.resolve()
    for name in ("task.v1.json","quality-plan.json","readback-manifest.json","holdout.oracle.json"):
        if not (q/name).is_file():fail("PILOT_EXTERNAL_INPUT_MISSING:"+name)
    if q==repo_path.resolve() or q.is_relative_to(repo_path.resolve()):fail("PILOT_OUTPUT_INSIDE_REPO")
    def digest(name):return sha_bytes((q/name).read_bytes())
    return ["programming-agent-worker","--provider",provider,"--model",model,
            "--repo-path",str(repo_path.resolve()),"--task-spec",str(q/"task.v1.json"),
            "--quality-plan",str(q/"quality-plan.json"),"--quality-plan-sha256",digest("quality-plan.json"),
            "--readback-manifest",str(q/"readback-manifest.json"),"--readback-manifest-sha256",digest("readback-manifest.json"),
            "--hidden-oracle-manifest",str(q/"holdout.oracle.json"),"--hidden-oracle-sha256",digest("holdout.oracle.json"),
            "--max-output-tokens","8000","--output",str(q/"verified-worker-receipt.json"),
            "--patch-output",str(q/"worker.patch")]
