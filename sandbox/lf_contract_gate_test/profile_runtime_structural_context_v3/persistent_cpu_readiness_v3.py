#!/usr/bin/env python3
"""No-execution readiness probe for a persistent CPU llama.cpp runtime.

Validates local assets and builds the exact candidate command without spawning a model.
Safe for preflight on a persistent host; it does not perform network access or inference.
"""
from __future__ import annotations
import argparse, hashlib, json, os
from dataclasses import dataclass, asdict
from pathlib import Path

LLAMA_SOURCE_COMMIT='925e1179947ea0c0ebfb0032df18af3a729822be'
MODEL_SHA256='d02fe9b69ad8cadbbd228e387667af66612c44bed29ffc8eb1e7caf9ac486c12'
MMPROJ_SHA256='980c9b2f78c04e6cff93d277ada09e768394f112d75db3b4e9dea8a69f9fb904'
ARTIFACT_SHA256='ee36e056038832e9efbd0a369ded22808614c0c9a3f8ea7766e22f739ecdb287'

@dataclass(frozen=True)
class Readiness:
 ready: bool
 reasons: tuple[str,...]
 command: tuple[str,...]
 evidence: dict
 def to_dict(self): return asdict(self)

def sha256_file(path:Path)->str:
 h=hashlib.sha256()
 with path.open('rb') as f:
  for chunk in iter(lambda:f.read(1024*1024),b''): h.update(chunk)
 return h.hexdigest()

def inspect(*,llama_cli:Path,model:Path,mmproj:Path,image:Path,schema:Path,output:Path,
            model_sha256:str=MODEL_SHA256,mmproj_sha256:str=MMPROJ_SHA256,image_sha256:str=ARTIFACT_SHA256,
            context_tokens:int=16384,max_output_tokens:int=2048)->Readiness:
 reasons=[]; evidence={}
 for name,path in [('llama_cli',llama_cli),('model',model),('mmproj',mmproj),('image',image),('schema',schema)]:
  path=Path(path)
  if not path.is_file(): reasons.append(f'MISSING:{name}'); continue
  evidence[f'{name}_sha256']=sha256_file(path)
 if Path(llama_cli).is_file() and not os.access(llama_cli,os.X_OK): reasons.append('CLI_NOT_EXECUTABLE')
 if evidence.get('model_sha256')!=model_sha256: reasons.append('MODEL_SHA256_MISMATCH')
 if evidence.get('mmproj_sha256')!=mmproj_sha256: reasons.append('MMPROJ_SHA256_MISMATCH')
 if evidence.get('image_sha256')!=image_sha256: reasons.append('IMAGE_SHA256_MISMATCH')
 if Path(schema).is_file():
  try:
   payload=json.loads(Path(schema).read_text(encoding='utf-8'))
   if not isinstance(payload,dict): reasons.append('SCHEMA_NOT_OBJECT')
  except Exception: reasons.append('SCHEMA_INVALID_JSON')
 command=(str(llama_cli),'-m',str(model),'-mm',str(mmproj),'-c',str(context_tokens),'-n',str(max_output_tokens),'-t','4','--temp','0.2','--top-p','0.9','-s','42','-jf',str(schema),'--image',str(image),'-o',str(output))
 evidence['llama_source_commit']=LLAMA_SOURCE_COMMIT
 evidence['inference_executed']=False
 evidence['network_access_performed']=False
 return Readiness(not reasons,tuple(reasons),command,evidence)

def main()->int:
 ap=argparse.ArgumentParser();
 for name in ('llama-cli','model','mmproj','image','schema','output'): ap.add_argument('--'+name,required=True)
 ap.add_argument('--json-output')
 a=ap.parse_args(); r=inspect(llama_cli=Path(a.llama_cli),model=Path(a.model),mmproj=Path(a.mmproj),image=Path(a.image),schema=Path(a.schema),output=Path(a.output))
 text=json.dumps(r.to_dict(),ensure_ascii=False,indent=2,sort_keys=True)
 if a.json_output: Path(a.json_output).write_text(text+'\n',encoding='utf-8')
 print(text); return 0 if r.ready else 2
if __name__=='__main__': raise SystemExit(main())
