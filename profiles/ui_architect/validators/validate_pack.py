"""UI Architect deterministic pack entrypoint; no implicit writes or promotion."""
from __future__ import annotations
import json
import sys
from pathlib import Path
from runtime_validate import validate
from runtime_semantic_utility import evaluate

def main():
    if len(sys.argv)!=2:
        print(json.dumps({"status":"BLOCKED","code":"INPUT_FILE_REQUIRED"}));return 2
    try:
        payload=json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
        v=validate(payload);s=evaluate(payload,v)
        passed=v.get("status")==s.get("status")=="PASS"
        print(json.dumps({"status":"PASS" if passed else "BLOCKED","canonical":v,"semantic":s},ensure_ascii=False))
        return 0 if passed else 1
    except Exception as exc:
        print(json.dumps({"status":"BLOCKED","code":type(exc).__name__}));return 1
if __name__=="__main__":raise SystemExit(main())
