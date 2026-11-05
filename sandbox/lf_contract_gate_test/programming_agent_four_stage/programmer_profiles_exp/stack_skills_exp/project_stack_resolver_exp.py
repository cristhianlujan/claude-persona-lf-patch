"""Sandbox-only data-driven stack binding; never infers skill from profile names or AI.
Exact SKILL bytes are hash-pinned. DB must already pass local selector_exp_test_* guard.
"""
import copy,hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parent
ROLES=ROOT.parent
class StackBlocked(ValueError):pass
def block(x):raise StackBlocked(x)
def sha_bytes(data):return hashlib.sha256(data).hexdigest()
def sha_text(s):return sha_bytes(s.encode("utf-8"))
def load_json(name):return json.loads((ROOT/name).read_text(encoding="utf-8"))
def literal(s):
    if not isinstance(s,str) or not s or len(s)>160:block("SKILL_BINDING_INPUT_INVALID")
    return "'"+s.replace("'","''")+"'"
def skill_catalog():
    rows=load_json("skill_catalog_exp.json")["skills"]
    if len({r["skill_code"] for r in rows})!=len(rows):block("SKILL_CATALOG_DUPLICATE")
    return {r["skill_code"]:r for r in rows}
def skill_material(code):
    entry=skill_catalog().get(code)
    if not entry:block("SKILL_CODE_NOT_IN_CATALOG")
    path=(ROOT/entry["path"]).resolve()
    if not path.is_relative_to(ROOT.resolve()):block("SKILL_PATH_TRAVERSAL")
    data=path.read_bytes()
    text=data.decode("utf-8")
    if (not text.startswith("# ") or "CANDIDATE_SANDBOX_ONLY" not in text or
        "**Área declarada:** "+entry["area"] not in text or
        "**Código:** "+entry["skill_code"] not in text):
        block("SKILL_SOURCE_INVALID")
    return {"skill_code":code,"area":entry["area"],"skill_sha256":sha_bytes(data),
            "skill_text":text,"source_path":entry["path"],"standard_family":entry["standard_family"]}
def role_material(profile_code):
    slugs={"PERFIL-PROG-BACKEND-EXP":"prog_backend_exp","PERFIL-PROG-FRONTEND-EXP":"prog_frontend_exp","PERFIL-PROG-DATA-EXP":"prog_data_exp"}
    slug=slugs.get(profile_code)
    if not slug:block("PROFILE_ROLE_UNKNOWN")
    path=ROLES/slug/"SKILL.md"
    data=path.read_bytes()
    binding=json.loads((ROLES/slug/"contracts/runtime_binding.json").read_text())
    if binding["runtime_enabled"] is not False or binding["promotion_allowed"] is not False:block("ROLE_RUNTIME_ENABLED")
    if binding["profile_code"]!=profile_code:block("ROLE_CODE_MISMATCH")
    return {"profile_code":profile_code,"area":binding["area"],
            "profile_sha256":sha_bytes(data),"role_text":data.decode("utf-8"),
            "source_path":slug+"/SKILL.md"}
def pg00_source_status(code):
    row=next((r for r in load_json("pg00_catalog_sources_exp.json")["families"] if r["code"]==code),None)
    if not row:block("PG00_STD_FAMILY_UNKNOWN")
    # These are references in a PG00 migration, NOT the normative standard text.
    return {"standard_family":code,"standard_source_ref":load_json("pg00_catalog_sources_exp.json")["source_ref"],
            "normative_text_available":False,"blocker":"PG00_STANDARD_TEXT_UNAVAILABLE"}
def seed_local_binding_table(dsn,run_psql):
    # Only called after external disposable DB guard, never on Supabase.
    rows=load_json("project_stack_binding_fixtures.json")["rows"]
    for r in rows:
        m=skill_material(r["skill_code"])
        if m["area"]!=r["area"]:block("SKILL_AREA_MISMATCH")
        sql="INSERT INTO public.project_stack_binding_exp(project_ref,area,skill_code,skill_sha256) VALUES ("+",".join(literal(x) for x in [r["project_ref"],r["area"],r["skill_code"],m["skill_sha256"]])+")"
        run_psql(dsn,sql=sql)
def select_binding(project_ref,area,read_row):
    if area not in ("BACKEND","FRONTEND","DATA"):block("SKILL_AREA_INVALID")
    # Exact project/area readback from SQL table. Not a Python project->stack mapping.
    rows=read_row(project_ref,area)
    if not isinstance(rows,list) or len(rows)!=1:block("SKILL_NOT_BOUND")
    row=rows[0]
    if set(row)!={"project_ref","area","skill_code","skill_sha256"} or row["project_ref"]!=project_ref or row["area"]!=area:
        block("SKILL_BINDING_ROW_INVALID")
    material=skill_material(row["skill_code"])
    if material["area"]!=area:block("SKILL_AREA_MISMATCH")
    if row["skill_sha256"]!=material["skill_sha256"]:block("SKILL_SHA256_MISMATCH")
    return {**material,"project_ref":project_ref,"binding_row":row,
            "pg00":pg00_source_status(material["standard_family"])}
def read_sql_binding(dsn,run_psql,project_ref,area):
    def read(project,ar):
        statement="SELECT coalesce(jsonb_agg(to_jsonb(b)),'[]'::jsonb)::text FROM public.project_stack_binding_exp b WHERE project_ref="+literal(project)+" AND area="+literal(ar)
        return json.loads(run_psql(dsn,sql=statement))
    return select_binding(project_ref,area,read)
def compose_visible_worker_spec(spec,assignment,role,skill):
    if (assignment.get("profile_code")!=role["profile_code"] or
        assignment.get("area")!=role["area"] or
        assignment.get("project_ref")!=skill["project_ref"] or skill["area"]!=role["area"]):
        block("ROLE_SKILL_ASSIGNMENT_MISMATCH")
    if sha_text(role["role_text"])!=role["profile_sha256"]:block("PROFILE_SHA256_MISMATCH")
    if sha_text(skill["skill_text"])!=skill["skill_sha256"]:block("SKILL_SHA256_MISMATCH")
    if skill["pg00"]["standard_family"]!=skill["standard_family"]:block("PG00_STANDARD_FAMILY_MISMATCH")
    result=copy.deepcopy(spec)
    if not isinstance(result.get("functional_contract"),dict):block("WORKER_CONTRACT_INVALID")
    result["functional_contract"]["role_and_stack"]={
        "profile_code":role["profile_code"],"profile_sha256":role["profile_sha256"],
        "profile_rules":role["role_text"],
        "skill_code":skill["skill_code"],"skill_sha256":skill["skill_sha256"],
        "skill_rules":skill["skill_text"],
        "project_ref":skill["project_ref"],"area":skill["area"],
        "pg00_standard_source":skill["pg00"]}
    return result
