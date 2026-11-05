"""Strict source-first selector descriptor from each candidate SKILL.md.
Invokes the ORIGINAL resync function only in a disposable PostgreSQL test database.
"""
import hashlib,json,re
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
    return {"schema_version":"LF_PROFILE_SELECTION_DESCRIPTOR_V1",
            "description":purpose,"selection_evidence":[evidence]}
def candidates():
    return {CODE[s]:descriptor(s) for s in SLUGS}
def apply_local_resync(dsn,commit_sha,run_psql,sql_json):
    if not isinstance(commit_sha,str) or not re.fullmatch(r"[a-f0-9]{40}",commit_sha):
        raise ValueError("EXACT_CANDIDATE_HEAD_REQUIRED")
    for slug in SLUGS:
        code=CODE[slug]
        repo_path="sandbox/lf_contract_gate_test/programming_agent_four_stage/programmer_profiles_exp/"+slug
        def q(x):return "'"+x.replace("'","''")+"'"
        # Edits ONLY the local selector_exp_test_* fixture, after test harness guard().
        run_psql(dsn,sql="UPDATE public.lf_activos SET metadata=jsonb_set(metadata,'{repo_path}',to_jsonb("+q(repo_path)+"::text)) WHERE codigo_activo="+q(code))
        source_ref="https://github.com/cristhianlujan/claude-persona-lf-patch/blob/"+commit_sha+"/"+repo_path+"/SKILL.md"
        statement="SELECT public.lf_profile_selector_descriptor_sync_v1("+",".join([
            q(code),sql_json(descriptor(slug)),q("GITHUB_SKILL"),q(source_ref),
            q(commit_sha),q("SANDBOX_PROFILE_RESYNC_ONLY")])+")::text"
        outcome=json.loads(run_psql(dsn,sql=statement))
        if outcome.get("outcome")!="SYNCED" or outcome.get("profile_code")!=code:
            raise AssertionError("DESCRIPTOR_SYNC_FAILED:"+slug)
    return candidates()
