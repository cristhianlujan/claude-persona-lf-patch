#!/usr/bin/env python3
"""Visual-evidence passthrough wrapper for J02 v0.8.

Preserves the registered v0.8 decomposition semantics and adds a lossless
screen-ingestion/v0.2 observation coverage assertion without redefining units.
"""
from __future__ import annotations
import hashlib
from pathlib import Path
from typing import Any
import validate_screen_decomposition_v08 as legacy
from lf_common import ValidationInputError, failure, result_object

REGISTRATION="candidate://creating-integral-user-stories/ART_SCRIPT_VALIDATE_SCREEN_DECOMPOSITION_VISUAL"
EXTRA="visual_observation_coverage"
_orig_semantic=legacy.semantic
_orig_self_test=legacy.self_test
legacy.REGISTRATION=REGISTRATION
legacy.ASSERTIONS=(*legacy.ASSERTIONS,EXTRA)

def runtime_meta():
    path=Path(__file__).resolve(); raw=path.read_bytes()
    return {"semantic_validator_path":str(path),"semantic_validator_sha256":hashlib.sha256(raw).hexdigest(),"semantic_validator_git_blob_sha1":hashlib.sha1(f"blob {len(raw)}\0".encode()+raw).hexdigest(),"semantic_validator_bytes":len(raw)}
legacy.runtime_meta=runtime_meta

def semantic(target:str, ingestion:dict[str,Any], dec:dict[str,Any]):
    checks,evidence=_orig_semantic(target,ingestion,dec)
    missing=[]
    if ingestion.get("schema_version")=="screen-ingestion/v0.2":
        source={(str(x.get("observation_code") or ""),str(x.get("source_ref") or "")) for x in ingestion.get("visual_observation_inventory",[]) if isinstance(x,dict)}
        dest={(str(x.get("observation_code") or ""),str(x.get("source_ref") or "")) for x in dec.get("visual_observation_inventory",[]) if isinstance(x,dict)}
        missing=sorted(source-dest)
    checks[EXTRA]=len(missing)
    evidence["missing_visual_observations"]= [list(x) for x in missing]
    evidence["visual_observation_passthrough_count"]=len(dec.get("visual_observation_inventory") or [])
    evidence["checks"]=checks
    return checks,evidence
legacy.semantic=semantic

def self_test(): return _orig_self_test()
legacy.self_test=self_test

def main(): return legacy.main()
if __name__=="__main__": raise SystemExit(legacy.main_guard(legacy.JUDGE,main))
