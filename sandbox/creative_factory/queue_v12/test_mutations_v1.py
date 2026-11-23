"""V12 B11/B25/B28: two independent behavior mutants in CI disposable checkout."""
from __future__ import annotations

import hashlib
import os
import subprocess
import sys
from pathlib import Path

assert os.environ.get("GITHUB_ACTIONS")=="true"
assert os.environ.get("SALY_MUTATION_SANDBOX")=="1"
source_path=Path(__file__).with_name("chat_generation_flow_v1.py")
original=source_path.read_bytes()
source=original.decode()
expected_hash=hashlib.sha256(original).hexdigest()
root=Path(__file__).resolve().parents[3]
mutants=(
    ("PENDING_ONLY_FILTER",
     'if r.get("item_state") != "PENDIENTE":',
     'if False:',
     "test_completed_and_processing_ignored"),
    ("QA_COMMENT_READBACK",
     'and final.get("comment_persisted") is True,',
     'and True,',
     "test_missing_persisted_comment_blocks_terminado"),
)
try:
    for name,before,after,method in mutants:
        assert source.count(before)==1, "V12_TARGET_AMBIGUOUS:"+name
        source_path.write_text(source.replace(before,after))
        result=subprocess.run(
            [sys.executable,"-m","unittest","-v",
             "sandbox.creative_factory.queue_v12.test_chat_generation_flow_v1."
             "TestChatGenerationV12."+method],
            capture_output=True,text=True,timeout=40,cwd=root,check=False)
        combined=result.stdout+result.stderr
        # Wrong mutants must FAIL by the specifically targeted test assertion.
        expected=("AssertionError" if name=="PENDING_ONLY_FILTER"
                  else "ChatFlowRejected not raised")
        if result.returncode==0 or expected not in combined:
            raise AssertionError("V12_MUTANT_NOT_KILLED_BY_TARGET:"+name+":"+combined[-1600:])
        if "SyntaxError" in combined or "ModuleNotFoundError" in combined:
            raise AssertionError("V12_MUTANT_KILLED_BY_WRONG_CAUSE:"+name)
        print("V12_MUTANT_KILLED_BY_BEHAVIOR:"+name)
finally:
    source_path.write_bytes(original)
    assert hashlib.sha256(source_path.read_bytes()).hexdigest()==expected_hash,"V12_RESTORE_DRIFT"
print("PASS_V12_MUTANTS_2_OF_2_RESTORED")
