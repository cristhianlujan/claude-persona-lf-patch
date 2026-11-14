"""Include Step70 native reviewer and no-Issue Gate2 parser in PR R17 CI.

These checks never assert a real OpenAI model call or create a sandbox RUN.
"""
import subprocess
import sys
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
BASE=ROOT/"sandbox/lf_contract_gate_test/profile_execution_runtime"

class NativeModelContractR17(unittest.TestCase):
    def test_step70_same_llm_negative_and_evaluator(self):
        p=subprocess.run([sys.executable,"-m","unittest","discover","-s",str(BASE),
             "-p","test_step70_same_llm_separate_call_v1.py","-v"],
             cwd=str(ROOT),text=True,capture_output=True,timeout=35)
        self.assertEqual(p.returncode,0,p.stdout[-1500:]+"\n"+p.stderr[-3500:])

    def test_issue_free_gate2_parser_contract(self):
        p=subprocess.run([sys.executable,"-m","unittest","discover","-s",str(BASE),
             "-p","test_profile_direct_gate2_dispatch_v1.py","-v"],
             cwd=str(ROOT),text=True,capture_output=True,timeout=35)
        self.assertEqual(p.returncode,0,p.stdout[-1500:]+"\n"+p.stderr[-3500:])

if __name__=="__main__":unittest.main()
