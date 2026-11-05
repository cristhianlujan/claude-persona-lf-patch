#!/usr/bin/env python3
"""6 deterministic positive/adversarial cases per candidate pack."""
import copy
import json
import sys
from pathlib import Path

PACK=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(PACK/"validators"))
from validate_pack import validate

def test():
    specimen=json.loads((PACK/"examples/good_output.json").read_text())
    packet=json.loads((PACK/"fixtures/happy_path/input.json").read_text())
    binding=json.loads((PACK/"runtime_binding.json").read_text())
    schema=json.loads((PACK/"schemas/output.schema.json").read_text())
    cases=[]
    cases.append(("VALID_VISIBLE_SPEC",copy.deepcopy(specimen),copy.deepcopy(packet),True))
    outside=copy.deepcopy(specimen);outside["write_path_patterns"]=["src/not-in-lot.py"]
    cases.append(("OUTSIDE_LOT",outside,copy.deepcopy(packet),False))
    empty=copy.deepcopy(specimen);empty["required_tests"]=[]
    cases.append(("EMPTY_TESTS",empty,copy.deepcopy(packet),False))
    oracle=copy.deepcopy(specimen);oracle["oracle_envelope"]={"commands":["hidden"]}
    cases.append(("HIDDEN_ORACLE",oracle,copy.deepcopy(packet),False))
    area=copy.deepcopy(packet);area["area"]="WRONG_AREA"
    cases.append(("WRONG_AREA",copy.deepcopy(specimen),area,False))
    authority=copy.deepcopy(specimen);authority["production_authority"]=True
    cases.append(("INJECTED_AUTHORITY",authority,copy.deepcopy(packet),False))
    for name,output,inp,expected in cases:
        errors=validate(output,binding,inp,schema)
        actual=not errors
        assert actual==expected,(name,errors)
        print("PASS",binding["profile_code"],name, "ACCEPTED" if actual else "BLOCKED",",".join(errors))
    print("PASS",len(cases),"/",len(cases),binding["profile_code"])

if __name__=="__main__":
    test()
