"""Strict source-first selector descriptor from each candidate SKILL.md.
Invokes the ORIGINAL resync function only in a disposable PostgreSQL test database.
"""
import hashlib,json,re,os
from urllib.parse import urlsplit,unquote
from pathlib import Path
ROOT=Path(__file__).resolve().parent
SLUGS=("prog_backend_exp","prog_frontend_exp","prog_data_exp")
CODE={"prog_backend_exp":"PERFIL-PROG-BACKEND-EXP","prog_frontend_exp":"PERFIL-PROG-FRONTEND-EXP","prog_data_exp":"PERFIL-PROG-DATA-EXP"}
def descriptor(slug):
    if slug not in SLUGS:raise ValueError("PROFILE_UNKNOWN")
    skill=(ROOT/slug/"SKILL.md").read_text(encoding="utf-8")
    def exactly(marker):
        items=re.findall(r"^- "+re.escape(marker)+r": (.+)$",skill,re.M)
        if len(items)!=1:raise ValueError("SKILL_DESCRIPTOR_FIELD_MISSING_OR_DUPLICATE:"+marker)
        return items[0].strip()
    purpose=exactly("PROFILE_SELECTION_DESCRIPTION")
    area=exactly("DECLARED_AREA")
    if area not in ("BACKEND","FRONTEND","DATA") or not purpose:raise ValueError("SKILL_DESCRIPTOR_INVALID")
    evidence={"kind":exactly("PROFILE_SELECTION_EVIDENCE_KIND"),
              "source_section":exactly("PROFILE_SELECTION_EVIDENCE_SECTION"),
              "value":purpose}
    if evidence["kind"]!="PURPOSE" or evidence["source_section"]!="Purpose":raise ValueError("EVIDENCE_UNBOUND")
    real_path="sandbox/lf_contract_gate_test/programming_agent_four_stage/programmer_profiles_exp/"+slug+"/SKILL.md"
    return {"schema_version":"LF_PROFILE_SELECTION_DESCRIPTOR_V1",
            "description":purpose,"selection_evidence":[evidence],
            "sandbox_source_path":real_path,
            "sandbox_source_sha256":hashlib.sha256(skill.encode("utf-8")).hexdigest()}
def candidates():
    return {CODE[s]:descriptor(s) for s in SLUGS}
def apply_local_resync(dsn,commit_sha,run_psql,sql_json):
    # This function writes ONLY to a local disposable PostgreSQL fixture. Fail closed.
    u=urlsplit(dsn)
    if (os.environ.get("SELECTOR_EXP_DISPOSABLE_DB")!="YES"
        or u.scheme not in ("postgresql","postgres")
        or u.hostname not in ("127.0.0.1","::1","localhost")
        or not unquote(u.path.lstrip("/")).startswith("selector_exp_test_")
        or u.query or u.fragment):
        raise ValueError("DISPOSABLE_LOCAL_DATABASE_REQUIRED")
    line=run_psql(dsn,sql="SELECT current_database()||'|'||coalesce(host(inet_server_addr()),'SOCKET')")
    name,ip=line.split("|")
    if name!=unquote(u.path.lstrip("/")) or ip not in ("127.0.0.1","::1"):
        raise ValueError("DISPOSABLE_DATABASE_SERVER_NOT_LOCAL")
    if not isinstance(commit_sha,str) or not re.fullmatch(r"[a-f0-9]{40}",commit_sha):
        raise ValueError("EXACT_CANDIDATE_HEAD_REQUIRED")
    for slug in SLUGS:
        code=CODE[slug]
        # The original selector's eligibility gate only permits canonical profiles/*.
        # The virtual source below is an example.invalid ALIAS FOR LOCAL FIXTURES,
        # NOT A REAL GITHUB PROFILE. Real SKILL source + SHA are in the descriptor.
        # Never create this alias in production or use it for runtime admission.
        virtual_repo_path="profiles/"+slug
        def q(x):return "'"+x.replace("'","''")+"'"
        source_ref="https://example.invalid/"+virtual_repo_path+"/SKILL.md#local-fixture="+commit_sha
        statement="SELECT public.lf_profile_selector_descriptor_sync_v1("+",".join([
            q(code),sql_json(descriptor(slug)),q("GITHUB_SKILL"),q(source_ref),
            q(commit_sha),q("SANDBOX_PROFILE_RESYNC_ONLY")])+")::text"
        outcome=json.loads(run_psql(dsn,sql=statement))
        if outcome.get("outcome")!="SYNCED" or outcome.get("profile_code")!=code:
            raise AssertionError("DESCRIPTOR_SYNC_FAILED:"+slug)
    return candidates()
