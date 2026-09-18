#!/usr/bin/env python3
from __future__ import annotations
import importlib.util, json, tempfile
from pathlib import Path
HERE=Path(__file__).resolve().parent
MATRIX=HERE/"gate_check_observability_assurance_matrix_v1.json"
GROUP_RUNNER=HERE/"run_gate_groups_v1.py"
EKB=HERE/"persist_gate_failures_to_ekb_v1.py"
def load(path,name):
    spec=importlib.util.spec_from_file_location(name,path); mod=importlib.util.module_from_spec(spec); assert spec and spec.loader; spec.loader.exec_module(mod); return mod
def main():
    data=json.loads(MATRIX.read_text(encoding="utf-8"))
    assert data["capability_code"]=="GATE_CHECK_OBSERVABILITY"
    groups=load(GROUP_RUNNER,"gco_groups"); ekb=load(EKB,"gco_ekb")
    a=ekb.stable_error_code("G","G01","x/test.py","AssertionError")
    assert a==ekb.stable_error_code("G","G01","x/test.py","AssertionError")
    assert a!=ekb.stable_error_code("G","G01","x/test.py","TimeoutError")
    src=EKB.read_text(encoding="utf-8").lower()
    assert "lf_write_pipeline_ekb_v1" not in src
    assert "public.lf_operation_gate_check_results" in src
    assert "public.lf_record_gate_checks_v1" in src
    assert "pre_ekb_gate" in src
    for forbidden in ("insert into transversal.error_knowledge","update transversal.error_knowledge","insert into public.lf_error_knowledge","update public.lf_error_knowledge"):
        assert forbidden not in src
    engine=GROUP_RUNNER.read_text(encoding="utf-8")
    for forbidden in ("PROFILE_RUNTIME","CURRENTNESS_AUTHORITY","PARITY"):
        assert forbidden not in engine
    with tempfile.TemporaryDirectory() as td:
        root=Path(td); tests=[]
        for i in range(2):
            p=root/f"test_{i}.py"; p.write_text("print('ok')\n",encoding="utf-8"); tests.append(str(p))
        manifest={"schema_version":"lf-gate-group-manifest/v1","consumer_code":"Q","gate_id":"QG","owner":"GATE_CHECK_OBSERVABILITY","discover_glob":str(root/"test_*.py"),"expected_total_checks":2,"groups":[{"group_id":"Q01","execution_class":"DETERMINISTIC","tests":[tests[0]]},{"group_id":"Q02","execution_class":"DETERMINISTIC","tests":[tests[1]]}]}
        mp=root/"manifest.json"; mp.write_text(json.dumps(manifest),encoding="utf-8")
        loaded=groups.load_manifest(mp); assert loaded["expected_total_checks"]==2
        tampered=dict(manifest); tampered["expected_total_checks"]=3; mp.write_text(json.dumps(tampered),encoding="utf-8")
        try: groups.load_manifest(mp)
        except ValueError as exc: assert "discovered_count_mismatch" in str(exc)
        else: raise AssertionError("tampered manifest did not block")
    print("GATE_CHECK_OBSERVABILITY_CLAIM_ASSURANCE_REGRESSION_PASS")
if __name__=="__main__": main()
