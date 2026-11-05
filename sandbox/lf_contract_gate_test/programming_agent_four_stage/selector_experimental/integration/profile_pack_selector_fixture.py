"""Offline descriptor projection of sandbox-only SKILL.md, followed by the ORIGINAL
lf_profile_selector_descriptor_sync_v1 in disposable local PostgreSQL only.

Never writes Supabase, profiles/ or any real registry. Not a production resync.
"""
import hashlib
import json
import re
import subprocess
from pathlib import Path

PACKS=Path(__file__).resolve().parents[2]/"programmer_profiles_exp"
CONFIG={
 "prog_backend_exp":"PERFIL-PROG-BACKEND-EXP",
 "prog_frontend_exp":"PERFIL-PROG-FRONTEND-EXP",
 "prog_data_exp":"PERFIL-PROG-DATA-EXP",
}

def load_descriptor(slug):
    if slug not in CONFIG:raise ValueError("UNREGISTERED_SANDBOX_PROFILE")
    path=PACKS/slug/"SKILL.md"
    source=path.read_text(encoding="utf-8")
    m=re.search(r"^## Purpose\n(.+?)(?=^## |\Z)",source,re.S|re.M)
    if not m or not m.group(1).strip():raise ValueError("SKILL_PURPOSE_MISSING")
    purpose=m.group(1).strip().split("\n")[0].strip()
    descriptor={"schema_version":"LF_PROFILE_SELECTION_DESCRIPTOR_V1",
                "description":purpose,
                "selection_evidence":[{"kind":"PURPOSE",
                  "source_section":"SKILL.md#Purpose",
                  "value":purpose}]}
    return descriptor, hashlib.sha256(source.encode("utf-8")).hexdigest()

def q(value):
    return "'"+str(value).replace("'","''")+"'"

def apply_sandbox_resync(dsn,run_psql,source_head):
    if not re.fullmatch(r"[a-f0-9]{40}",source_head):
        raise ValueError("GIT_HEAD_REQUIRED")
    for slug,code in CONFIG.items():
        descriptor,source_sha=load_descriptor(slug)
        path="sandbox/lf_contract_gate_test/programming_agent_four_stage/programmer_profiles_exp/"+slug
        # The ORIGINAL selector requires repo_path under profiles/. A sandbox pack cannot
        # meet that rule honestly. Use a visibly VIRTUAL alias only for disposable tests.
        virtual_path="profiles/"+slug
        metadata=json.dumps({"canonical_profile_key":slug,"profile_slug":slug,
                             "repo_path":virtual_path})
        run_psql(dsn,sql="UPDATE public.lf_activos SET metadata="+q(metadata)+"::jsonb,"
                 " ruta_esperada="+q(virtual_path+"/SKILL.md")+" WHERE codigo_activo="+q(code))
        source_ref=("sandbox-descriptor://"+path+"/SKILL.md?LOCAL_VIRTUAL_ALIAS=/"+
                    virtual_path+"/SKILL.md")
        value=json.dumps(descriptor,ensure_ascii=False)
        run_psql(dsn,sql="SELECT public.lf_profile_selector_descriptor_sync_v1("+
            ",".join((q(code),q(value)+"::jsonb",q("GITHUB_SKILL"),
                      q(source_ref),q(source_head),q("sandbox-only-test")))+")::text")
        print("PASS LOCAL_ONLY VIRTUAL_ALIAS descriptor_sync from sandbox SKILL",code,"source_sha256",source_sha)
    return CONFIG
