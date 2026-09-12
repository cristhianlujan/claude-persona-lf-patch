#!/usr/bin/env python3
import importlib.util, json, os, sys, tempfile
from pathlib import Path
p=Path(__file__).with_name('persistent_cpu_readiness_v3.py')
s=importlib.util.spec_from_file_location('persistent_cpu_readiness_v3',p);m=importlib.util.module_from_spec(s);sys.modules[s.name]=m;s.loader.exec_module(m)
with tempfile.TemporaryDirectory() as td:
 d=Path(td); cli=d/'llama-cli'; model=d/'model.gguf'; mm=d/'mmproj.gguf'; image=d/'input.png'; schema=d/'schema.json'; output=d/'out.json'
 cli.write_text('#!/bin/sh\nexit 0\n'); cli.chmod(0o755); model.write_bytes(b'model'); mm.write_bytes(b'mmproj'); image.write_bytes(b'png'); schema.write_text('{"type":"object"}')
 good=m.inspect(llama_cli=cli,model=model,mmproj=mm,image=image,schema=schema,output=output,model_sha256=m.sha256_file(model),mmproj_sha256=m.sha256_file(mm),image_sha256=m.sha256_file(image))
 assert good.ready and not good.reasons
 assert good.evidence['inference_executed'] is False and good.evidence['network_access_performed'] is False
 assert '-jf' in good.command and '--image' in good.command and '-o' in good.command
 bad=m.inspect(llama_cli=cli,model=model,mmproj=mm,image=image,schema=schema,output=output,model_sha256='0'*64,mmproj_sha256=m.sha256_file(mm),image_sha256=m.sha256_file(image))
 assert not bad.ready and 'MODEL_SHA256_MISMATCH' in bad.reasons
 schema.write_text('not-json'); bad2=m.inspect(llama_cli=cli,model=model,mmproj=mm,image=image,schema=schema,output=output,model_sha256=m.sha256_file(model),mmproj_sha256=m.sha256_file(mm),image_sha256=m.sha256_file(image))
 assert not bad2.ready and 'SCHEMA_INVALID_JSON' in bad2.reasons
 cli.chmod(0o644); bad3=m.inspect(llama_cli=cli,model=model,mmproj=mm,image=image,schema=d/'missing.json',output=output,model_sha256=m.sha256_file(model),mmproj_sha256=m.sha256_file(mm),image_sha256=m.sha256_file(image))
 assert not bad3.ready and 'CLI_NOT_EXECUTABLE' in bad3.reasons and 'MISSING:schema' in bad3.reasons
print('PERSISTENT_CPU_READINESS_V3_PASS 8/8')
