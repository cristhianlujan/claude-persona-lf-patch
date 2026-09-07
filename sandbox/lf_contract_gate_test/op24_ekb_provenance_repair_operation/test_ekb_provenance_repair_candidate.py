#!/usr/bin/env python3
import copy
import importlib.util
from pathlib import Path
import yaml

ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('validator',ROOT/'validate_ekb_provenance_repair_candidate.py')
validator=importlib.util.module_from_spec(spec); spec.loader.exec_module(validator)

def load(name):
    with (ROOT/name).open('r',encoding='utf-8') as fh: return yaml.safe_load(fh)

contract=load('contrato_ekb_provenance_repair_lf.yaml')
steps=load('ekb_provenance_repair_lf_steps.yaml')
judge=load('judge_ekb_provenance_repair_lf.yaml')
assert validator.validate(contract,steps,judge)==[]

cases=[]
c=copy.deepcopy(contract); c['state_ceiling']['production_write_allowed_by_candidate']=True
cases.append(('production_write',c,steps,judge,'CANDIDATE_PRODUCTION_WRITE_ALLOWED'))
c=copy.deepcopy(contract); c['write_contract']['source_ref_overwrite_forbidden']=False
cases.append(('overwrite',c,steps,judge,'SOURCE_REF_OVERWRITE_NOT_FORBIDDEN'))
c=copy.deepcopy(contract); c['write_contract']['inferred_lote_or_sibling_provenance_forbidden']=False
cases.append(('inference',c,steps,judge,'INFERRED_PROVENANCE_NOT_FORBIDDEN'))
s=copy.deepcopy(steps); s['steps'][4]['order']=99
cases.append(('step_gap',contract,s,judge,'STEP_ORDER_NOT_CONTIGUOUS'))
j=copy.deepcopy(judge); j['required_assertions']=[x for x in j['required_assertions'] if x['id']!='rollback']
cases.append(('judge_rollback',contract,steps,j,'JUDGE_ASSERTIONS_MISSING:rollback'))
c=copy.deepcopy(contract); c['router_binding_candidate']['requires_existing_target']=False
cases.append(('router_existing',c,steps,judge,'ROUTER_BINDING_MISMATCH:requires_existing_target'))

for name,c_doc,s_doc,j_doc,expected in cases:
    errors=validator.validate(c_doc,s_doc,j_doc)
    assert expected in errors,(name,expected,errors)

print(f'PASS_EKB_PROVENANCE_REPAIR_ADVERSARIAL_TESTS {1+len(cases)}/{1+len(cases)}')
