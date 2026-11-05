#!/usr/bin/env python3
"""Offline pack layout, validator, evals. No DB, network, Worker or code modification."""
import json
import subprocess
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parent
REPO=ROOT.parents[3]
TEMPLATE=REPO/"profiles"/"_template"
PACKS=("prog_backend_exp","prog_frontend_exp","prog_data_exp")
FILES={
 "README.md","SKILL.md","adapters/document_patch_adapter.md",
 "adapters/github_pack_adapter.md","checklists/preflight_checklist.md",
 "checklists/priority_checklist.md","contracts/main_contract.md",
 "contracts/missing_input_policy.md","evals/eval_matrix.json",
 "examples/bad_output.json","examples/good_output.json",
 "examples/self_repair_output.json","fixtures/happy_path/input.json",
 "fixtures/missing_inputs/input.json","fixtures/self_repair/bad_output.json",
 "fixtures/unsafe_or_blocked/input.json","handoffs/to_quality_pack.handoff.json",
 "judges/mini_judge.md","judges/score_rubric.md","manifest.json",
 "schemas/missing_input.schema.json","schemas/output.schema.json",
 "validators/validate_pack.py"
}

def main():
    assert TEMPLATE.is_dir(),"Template not available in repository checkout"
    template_files={str(p.relative_to(TEMPLATE)) for p in TEMPLATE.rglob("*") if p.is_file()}
    assert template_files==FILES,("TEMPLATE_LIST_DRIFT",sorted(template_files^FILES))
    print("PASS exact template file-list pin",len(FILES))
    for slug in PACKS:
        pack=ROOT/slug
        files={str(p.relative_to(pack)) for p in pack.rglob("*") if p.is_file()}
        assert FILES<=files,("PACK_MISSING_TEMPLATE_FILES",slug,sorted(FILES-files))
        assert files==FILES|{"runtime_binding.json","evals/run_cases.py"},("UNEXPECTED_PACK_FILE",slug,files)
        print("PASS template mirrored",slug)
        manifest=json.loads((pack/"manifest.json").read_text())
        runtime=json.loads((pack/"runtime_binding.json").read_text())
        assert manifest["document_status"]=="CANDIDATE_SANDBOX_ONLY"
        assert runtime["runtime_enabled"] is False and runtime["promotion_allowed"] is False
        print("PASS runtime/promotion disabled",slug)
        for command in (["validators/validate_pack.py","."],["evals/run_cases.py"]):
            p=subprocess.run([sys.executable,*command],cwd=pack,
                             text=True,capture_output=True,timeout=30)
            print(p.stdout,end="")
            assert p.returncode==0,(slug,command,p.stderr,p.stdout)
    print("PASS THREE_PROGRAMMER_PROFILE_PACKS_SANDBOX_ONLY")

if __name__=="__main__":main()
