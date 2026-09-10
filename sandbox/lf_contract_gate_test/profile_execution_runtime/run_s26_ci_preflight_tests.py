#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json, tempfile
from copy import deepcopy
from pathlib import Path
from s26_ci_preflight import *

def write(root:Path,rel:str,data:str="x\n"):
 p=root/rel; p.parent.mkdir(parents=True,exist_ok=True); p.write_text(data)
def pin(p:Path)->str:
 b=p.read_bytes(); return hashlib.sha1(f"blob {len(b)}\0".encode()+b).hexdigest()
def schema()->dict:
 return {"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","required":sorted(REQUIRED_TOP_LEVEL),"properties":{
 "schema":{"type":"string","const":"S26_CI_PREFLIGHT_MANIFEST_V1"},"run_scope":{"type":"string","const":RUN_SCOPE},"execution_scope_id":{"type":"string","const":EXECUTION_SCOPE_ID},
 "required_files":{"type":"array","minItems":4,"maxItems":4,"items":{"type":"string","minLength":1}},"required_scripts":{"type":"array","minItems":10,"maxItems":10,"items":{"type":"string","minLength":1}},"required_validators":{"type":"array","minItems":2,"maxItems":2,"items":{"type":"string","minLength":1}},
 "schemas":{"type":"array","minItems":1,"maxItems":1,"items":{"type":"object","required":["path","schema_role","run_id"],"properties":{"path":{"type":"string"},"schema_role":{"type":"string"},"run_id":{"type":"string"}},"additionalProperties":False}},
 "authority_sources":{"type":"array","minItems":2,"maxItems":2,"items":{"type":"object","required":["authority_type","source_ref","run_id"],"properties":{"authority_type":{"type":"string"},"source_ref":{"type":"string"},"run_id":{"type":"string"}},"additionalProperties":False}},
 "bindings":{"type":"array","minItems":2,"maxItems":2,"items":{"type":"object","required":["binding_id","target_ref","callable","probe_mode","run_id"],"properties":{"binding_id":{"type":"string"},"target_ref":{"type":"string"},"callable":{"type":"string"},"probe_mode":{"type":"string"},"expected_error":{"type":"string"},"run_id":{"type":"string"}},"additionalProperties":False}},
 "inputs":{"type":"array","minItems":1,"maxItems":1,"items":{"type":"object","required":["input_id","path","run_id"],"properties":{"input_id":{"type":"string"},"path":{"type":"string"},"run_id":{"type":"string"}},"additionalProperties":False}},
 "workflow_guards":{"type":"array","minItems":5,"maxItems":5,"items":{"type":"object","required":["workflow_path","job","preflight_marker","heavy_markers","run_id"],"properties":{"workflow_path":{"type":"string"},"job":{"type":"string"},"preflight_marker":{"type":"string"},"heavy_markers":{"type":"array","minItems":1,"maxItems":3,"items":{"type":"string"}},"run_id":{"type":"string"}},"additionalProperties":False}},
 "integrity_pins":{"type":"array","minItems":16,"maxItems":16,"items":{"type":"object","required":["path","git_blob_sha1","run_id"],"properties":{"path":{"type":"string"},"git_blob_sha1":{"type":"string","minLength":40},"run_id":{"type":"string"}},"additionalProperties":False}}},"additionalProperties":False}
def workflow()->str:
 def job(name,markers,pip=False,extras=""):
  dep=f"      - name: {PIP_STEP}\n        run: |\n          set -euo pipefail\n          {PIP_CMD}\n" if pip else ""
  tail="".join(f"      - name: {x}\n        run: |\n          echo ok\n" for x in markers)
  return f"  {name}:\n    steps:\n      - name: Checkout repository\n        uses: actions/checkout@v4\n      - name: {STEP}\n        run: |\n          set -euo pipefail\n          {CMD}\n{dep}{extras}{tail}"
 return "jobs:\n"+"".join(job(k,*v) for k,v in GUARDS.items())
def fixture(root:Path)->dict:
 write(root,"CLAUDE.md","authority\n"); write(root,f"{BASE}/README.md","runtime\n")
 write(root,f"{BASE}/validate_profile_execution.py","def validate_receipt(x): return ['ERR']\n")
 write(root,f"{BASE}/semantic_obligation_manifest.py","def validate_obligation_manifest(x): raise ValueError('MANIFEST_SCHEMA_INVALID')\n")
 # Materialize all scripts. Imports are omitted in fixture so static closure stays deterministic.
 for rel in SCRIPTS: write(root,rel,"x=1\n")
 write(root,SCHEMA,json.dumps(schema())); write(root,WORKFLOW,workflow())
 m={"schema":"S26_CI_PREFLIGHT_MANIFEST_V1","run_scope":RUN_SCOPE,"execution_scope_id":EXECUTION_SCOPE_ID,
 "required_files":sorted(FILES),"required_scripts":sorted(SCRIPTS),"required_validators":sorted(VALIDATORS),
 "schemas":[{"path":SCHEMA,"schema_role":"PREFLIGHT_MANIFEST","run_id":EXECUTION_SCOPE_ID}],
 "authority_sources":[{"authority_type":k,"source_ref":v,"run_id":EXECUTION_SCOPE_ID} for k,v in AUTHORITIES.items()],
 "bindings":[{"binding_id":k,"target_ref":v[0],"callable":v[1],"probe_mode":v[2],**({"expected_error":v[3]} if v[3] else {}),"run_id":EXECUTION_SCOPE_ID} for k,v in BINDINGS.items()],
 "inputs":[{"input_id":"CANONICAL_PREFLIGHT_MANIFEST","path":MANIFEST,"run_id":EXECUTION_SCOPE_ID}],
 "workflow_guards":[{"workflow_path":WORKFLOW,"job":k,"preflight_marker":STEP,"heavy_markers":list(v[0]),"run_id":EXECUTION_SCOPE_ID} for k,v in GUARDS.items()]}
 write(root,MANIFEST,"{}\n"); m["integrity_pins"]=[{"path":rel,"git_blob_sha1":pin(root/rel),"run_id":EXECUTION_SCOPE_ID} for rel in sorted(PIN_PATHS)]; write(root,MANIFEST,json.dumps(m)); return m
def block(name,m,root,needle):
 try: validate_manifest(root,m)
 except PreflightError as e:
  assert needle in str(e),(name,needle,str(e)); return
 raise AssertionError(name+": expected block")
def repin(m,root,rel):
 for r in m["integrity_pins"]:
  if r["path"]==rel: r["git_blob_sha1"]=pin(root/rel); return
 raise AssertionError(rel)
def main():
 with tempfile.TemporaryDirectory() as td:
  r=Path(td); good=fixture(r); out=validate_manifest(r,good); assert out["status"]=="PASS_S26_CHEAP_PREFLIGHT" and out["workflow_guards"]==5
  required=0; audit=0; mutation=0
  def req(name,m,needle):
   nonlocal required; block(name,m,r,needle); required+=1
  def adv(name,m,needle):
   nonlocal audit; block(name,m,r,needle); audit+=1
  c=deepcopy(good); c.pop("bindings"); req("manifest_incomplete",c,"MANIFEST_INCOMPLETE")
  c=deepcopy(good); c["required_files"][0]="missing"; req("missing_file",c,"REQUIRED_FILE_DECLARATION_INVALID")
  c=deepcopy(good); c["authority_sources"]=c["authority_sources"][:1]; req("authority_missing",c,"MANIFEST_SCHEMA_VALIDATION_FAILED")
  c=deepcopy(good); c["bindings"]=c["bindings"][:1]; req("binding_missing",c,"MANIFEST_SCHEMA_VALIDATION_FAILED")
  sp=r/SCHEMA; old=sp.read_text(); sp.write_text("{"); c=deepcopy(good); repin(c,r,SCHEMA); req("invalid_schema",c,"SCHEMA_INVALID_JSON"); sp.write_text(old)
  rel=next(iter(SCRIPTS)); p=r/rel; old=p.read_text(); p.unlink(); req("script_missing",deepcopy(good),"REQUIRED_FILE_MISSING"); write(r,rel,old)
  c=deepcopy(good); c["bindings"][0]["run_id"]="S26-OTHER"; req("cross_run",c,"CROSS_RUN_REFERENCE")
  mp=r/MANIFEST; old=mp.read_text(); mp.unlink(); req("input_absent",deepcopy(good),"REQUIRED_FILE_MISSING"); write(r,MANIFEST,old)
  c=deepcopy(good); c["authority_sources"][0]["source_ref"]="x"; adv("authority_rebind",c,"SOURCE_AUTHORITY_REF_MISMATCH")
  c=deepcopy(good); c["bindings"][0]["callable"]="x"; adv("validator_rebind",c,"VALIDATOR_BINDING_MISMATCH")
  c=deepcopy(good); c["workflow_guards"]=c["workflow_guards"][:-1]; adv("guard_drop",c,"MANIFEST_SCHEMA_VALIDATION_FAILED")
  c=deepcopy(good); c["required_scripts"]=c["required_scripts"][:-1]; adv("script_decl_drop",c,"REQUIRED_SCRIPT_DECLARATION_INVALID")
  c=deepcopy(good); c["execution_scope_id"]="S26-X"; adv("scope_rebind",c,"EXECUTION_SCOPE_ID_INVALID")
  # Workflow bypasses: modify bytes then repin so structure, not integrity pin, must catch them.
  wp=r/WORKFLOW; original=wp.read_text()
  for name,needle,expected in [
   ("continue_on_error",f"      - name: {STEP}\n",f"      - name: {STEP}\n        continue-on-error: true\n"),
   ("if_false",f"      - name: {STEP}\n",f"      - name: {STEP}\n        if: false\n"),
   ("setup_before",f"      - name: {STEP}\n",f"      - name: Set up Python\n        uses: actions/setup-python@v5\n      - name: {STEP}\n")]:
   wp.write_text(original.replace(needle,expected,1)); c=deepcopy(good); repin(c,r,WORKFLOW); adv(name,c,"PREFLIGHT" if name!="setup_before" else "NONCHECKOUT_STEP_BEFORE_PREFLIGHT"); wp.write_text(original)
  # unsupported schema keyword remains rejected even if repinned
  s=json.loads(old if False else (r/SCHEMA).read_text()); s["patternProperties"]={}; (r/SCHEMA).write_text(json.dumps(s)); c=deepcopy(good); repin(c,r,SCHEMA); adv("unsupported_schema",c,"SCHEMA_UNSUPPORTED_KEYWORD"); (r/SCHEMA).write_text(json.dumps(schema()))
  # integrity mutation
  ap=r/"CLAUDE.md"; aold=ap.read_text(); ap.write_text("tamper\n"); adv("pin_tamper",deepcopy(good),"INTEGRITY_PIN_MISMATCH"); ap.write_text(aold)
  # Matrix: every declared canonical script deletion must block.
  for rel in sorted(SCRIPTS):
   p=r/rel; data=p.read_text(); p.unlink(); block("delete_"+rel,deepcopy(good),r,"REQUIRED_FILE_MISSING"); mutation+=1; write(r,rel,data)
  for field in ("authority_sources","bindings","workflow_guards","integrity_pins"):
   for i in range(len(good[field])):
    c=deepcopy(good); c[field][i]["run_id"]="S26-OTHER"; block(f"cross_{field}_{i}",c,r,"CROSS_RUN_REFERENCE"); mutation+=1
  print(f"PASS_S26_CI_PREFLIGHT_TESTS required_negative_cases={required}/8 audit_regressions={audit}/{audit} mutation_cases={mutation}/{mutation} valid_cases=1/1")
 return 0
if __name__=="__main__": raise SystemExit(main())
