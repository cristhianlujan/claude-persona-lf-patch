#!/usr/bin/env python3
"""Compile paired source projections from an immutable Git baseline.
This is PHYSICAL DELIVERY proof only; no model call, judge or authority write.
"""
from __future__ import annotations
import argparse, hashlib, json, subprocess
from pathlib import Path

HERE=Path(__file__).resolve().parent
import sys
RUNTIME_PATH=HERE.parents[3]/"sandbox/lf_contract_gate_test/profile_execution_runtime"
if str(RUNTIME_PATH) not in sys.path:sys.path.insert(0,str(RUNTIME_PATH))
from profile_runtime_runner import build_runtime_request
MANIFEST=HERE/"shadow_manifest_v1.json"
CASES=HERE/"cases_v1.json"

def sha(value: str)->str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()

def git(repo:Path,*args:str)->str:
    return subprocess.check_output(["git","-C",str(repo),*args],text=True).strip()

def sections(text:str)->tuple[str,dict[str,list[str]]]:
    lines=text.splitlines()
    if not lines or not lines[0].startswith("# "):
        raise ValueError("PROFILE_TITLE_MISSING")
    ordered:dict[str,list[str]]={}
    current=None
    for line in lines:
        if line.startswith("## "):
            current=line[3:].strip()
            if current in ordered:
                raise ValueError("DUPLICATE_H2:"+current)
            ordered[current]=[line]
        elif current is not None:
            ordered[current].append(line)
    return lines[0],ordered

def projected(text:str,include:list[str])->str:
    title,found=sections(text)
    if not include or len(set(include))!=len(include):
        raise ValueError("PROJECTION_SELECTION_INVALID")
    if any(name not in found for name in include):
        raise ValueError("PROJECTION_SECTION_MISSING")
    return title+"\n\n"+"\n\n".join("\n".join(found[n]).strip() for n in include)+"\n"

def inject(full:str,section:str,method:str)->str:
    # Preserve everything, injecting the method under the exact existing H2.
    if not method.startswith("### Behavioral method:") or "## " in method.replace("### ",""):
        raise ValueError("METHOD_HEADING_INVALID")
    lines=full.splitlines(keepends=True)
    indexes=[i for i,s in enumerate(lines) if s.rstrip("\r\n")=="## "+section]
    if len(indexes)!=1:
        raise ValueError("TARGET_SECTION_NOT_UNIQUE:"+section)
    begin=indexes[0]+1
    end=next((i for i in range(begin,len(lines)) if lines[i].startswith("## ")),len(lines))
    # Do not displace the next H2 or create a non-projected sidecar.
    return "".join(lines[:end])+"\n"+method.rstrip()+"\n\n"+"".join(lines[end:])

def compile_pair(repo:Path,revision:str,out:Path)->dict:
    manifest=json.loads(MANIFEST.read_text())
    cases=json.loads(CASES.read_text())
    projection=json.loads((repo/manifest["projection_contract"]).read_text())
    pmap={p["profile_slug"]:p for p in projection["profiles"]}
    records={}
    for p in manifest["profiles"]:
        slug=p["slug"];profile_ref=f"profiles/{slug}/SKILL.md"
        baseline=git(repo,"show",revision+":"+profile_ref)+"\n"
        method=(HERE/p["method_file"]).read_text()
        candidate=inject(baseline,p["target_section"],method)
        include=pmap[slug]["include_sections"]
        if p["target_section"] not in include:
            raise ValueError("METHOD_NOT_IN_RUNTIME_PROJECTION:"+slug)
        projected_baseline=projected(baseline,include)
        projected_candidate=projected(candidate,include)
        if method.strip() not in projected_candidate or method.strip() in projected_baseline:
            raise ValueError("PHYSICAL_DELIVERY_NOT_PROVEN:"+slug)
        if len(projected_candidate)>projection["max_projected_chars"]:
            raise ValueError("SOURCE_PROJECTION_BUDGET_EXCEEDED:"+slug)
        if sha(baseline)==sha(candidate):
            raise ValueError("NO_SHADOW_CHANGE:"+slug)
        sub=out/slug
        sub.mkdir(parents=True,exist_ok=True)
        for name,source in (("baseline_full",baseline),("candidate_full",candidate),
                            ("baseline_model_context",projected_baseline),
                            ("candidate_model_context",projected_candidate)):
            (sub/(name+".md")).write_text(source,encoding="utf-8")
        records[slug]={
            "profile_ref":profile_ref,
            "profile_code":p["profile_code"],
            "source_revision":revision,
            "target_section":p["target_section"],
            "baseline_full_sha256":sha(baseline),
            "candidate_full_sha256":sha(candidate),
            "baseline_context_sha256":sha(projected_baseline),
            "candidate_context_sha256":sha(projected_candidate),
            "behavior_method_sha256":sha(method),
            "model_source_delivery":"PASS",
            "source_unchanged":git(repo,"show",revision+":"+profile_ref)+"\n"==baseline,
            "baseline_model_context_path":str(sub/"baseline_model_context.md"),
            "candidate_model_context_path":str(sub/"candidate_model_context.md"),
        }
    pairings=[]
    for case in cases["cases"]:
        slug=case["profile_slug"]
        if slug not in records: raise ValueError("UNRESOLVED_PROFILE:"+slug)
        for arm in ("A_ORIGINAL","D_SHADOW"):
            phase="baseline" if arm=="A_ORIGINAL" else "candidate"
            model_path=records[slug][phase+"_model_context_path"]
            full_path=out/slug/(phase+"_full.md")
            request=build_runtime_request(
                execution_id="PE10_C3_SOURCE_PREFLIGHT:"+case["case_id"]+":"+arm,
                profile_code=records[slug]["profile_code"],profile_slug=slug,
                profile_sources=[{"ref":records[slug]["profile_ref"],"content":full_path.read_text()}],
                input_literal=case["prompt"])
            if request["input_sha256"]!=sha(case["prompt"]):
                raise ValueError("RUNTIME_REQUEST_INPUT_SHA_MISMATCH")
            pairings.append({
                "case_id":case["case_id"],"arm":arm,"profile_slug":slug,
                "prompt":case["prompt"],"input_sha256":sha(case["prompt"]),
                "model_context_path":model_path,
                "model_context_sha256":sha(Path(model_path).read_text()),
                "runtime_binding_status":"REQUEST_PREVIEW_PASS",
                "runtime_request_sha256":request["request_sha256"],
                "runtime_profile_source_sha256":request["profile_source_sha256"],
                "raw_response_status":"NOT_EXECUTED",
                "model_provider_attested":False,
            })
    result={
        "schema":"PE10_C3_FUNCTIONAL_SOURCE_DELIVERY_V1",
        "status":"PROJECTION_PASS_EXECUTION_PENDING",
        "immutable_baseline_revision":revision,
        "semantic_performance_demonstrated":False,
        "provider_attestation_claimed":False,
        "scope":"NON_AUTHORITY_SHADOW",
        "case_count":len(cases["cases"]),
        "paired_run_count":len(pairings),
        "profiles":records,"paired_assignments":pairings,
    }
    (out/"compilation_receipt.json").write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n")
    return result

def main()->int:
    p=argparse.ArgumentParser()
    p.add_argument("--repo",type=Path,required=True)
    p.add_argument("--revision",default="HEAD")
    p.add_argument("--out",type=Path,required=True)
    args=p.parse_args()
    repo=args.repo.resolve();out=args.out.resolve()
    if out==repo or repo in out.parents:
        raise SystemExit("OUTPUT_MUST_BE_OUTSIDE_AUTHORITY_REPOSITORY")
    revision=git(repo,"rev-parse",args.revision+"^{commit}")
    out.mkdir(parents=True,exist_ok=True)
    x=compile_pair(repo,revision,out)
    print(json.dumps({"status":x["status"],"revision":revision,
         "paired_run_count":x["paired_run_count"],
         "profiles":{k:v["model_source_delivery"] for k,v in x["profiles"].items()}},sort_keys=True))
    return 0

if __name__=="__main__":raise SystemExit(main())
