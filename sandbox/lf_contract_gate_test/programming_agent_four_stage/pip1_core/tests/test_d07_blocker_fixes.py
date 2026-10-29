"""Adversarial regressions for Claude's D-07 ALTA-1/2 and MEDIA-1/4."""
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from test_core import fixture
from pip1_core.core import (load_inventory, Pins, RunContract, Receipt, Outcome,
                            State, PIPError, transition, verify_closure)


class D07BlockerFixes(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'inventory.json'
        self.path.write_text(json.dumps(fixture(), ensure_ascii=False), encoding='utf8')
        self.outer = hashlib.sha256(self.path.read_bytes()).hexdigest()
        self.inv = load_inventory(self.path, expected_file_sha256=self.outer)
        self.run = RunContract('PIP-1','candidate','EXEC','RUN','EXECUTOR','SCOPE',
                 Pins('a'*40,'b'*64,'c'*64,self.inv.digest))

    def receipt(self, cp):
        return Receipt('EXEC','RUN',cp,'a'*40,self.run.pins.fingerprint(),
                       'fixture://explicit','e'*64,'PASS')

    def test_alta_1_b5_reject_forged_current_running(self):
        with self.assertRaisesRegex(PIPError, 'CURRENT_STATE_MISMATCH'):
            transition(State.RUNNING,State.SUCCEEDED_ACCREDITED,run=self.run,
                       checkpoint_id='PG-20.C1', inventory=self.inv,outcomes={})

    def test_alta_1_dependency_changed_between_eligible_and_running(self):
        outcomes={'PG-20.C1':Outcome(State.ELIGIBLE,'ELIGIBLE','fixture')}
        with self.assertRaisesRegex(PIPError,'DEPENDENCY_UNSATISFIED'):
            transition(State.ELIGIBLE,State.RUNNING,run=self.run,
                       checkpoint_id='PG-20.C1',inventory=self.inv,outcomes=outcomes)

    def test_alta_1_dependency_changed_before_success(self):
        outcomes={'PG-20.C1':Outcome(State.RUNNING,'RUNNING','fixture')}
        with self.assertRaisesRegex(PIPError,'DEPENDENCY_UNSATISFIED'):
            transition(State.RUNNING,State.SUCCEEDED_SYNTHETIC,run=self.run,
                       checkpoint_id='PG-20.C1',inventory=self.inv,outcomes=outcomes,
                       receipt=self.receipt('PG-20.C1'))

    def test_alta_2_b3_run_mismatch_transition(self):
        wrong=replace(self.run,pins=replace(self.run.pins,inventory_sha256='f'*64))
        with self.assertRaisesRegex(PIPError,'RUN_INVENTORY_PIN_MISMATCH'):
            transition(State.PENDING,State.ELIGIBLE,run=wrong,
                       checkpoint_id='PG-01.C1',inventory=self.inv,outcomes={})

    def test_alta_2_b3_run_mismatch_closure(self):
        wrong=replace(self.run,pins=replace(self.run.pins,inventory_sha256='f'*64))
        with self.assertRaisesRegex(PIPError,'RUN_INVENTORY_PIN_MISMATCH'):
            verify_closure(self.inv,wrong,{})

    def test_media_1_no_accredited_state_with_synthetic_receipt(self):
        outcomes={'PG-01.C1':Outcome(State.RUNNING,'RUNNING','fixture')}
        with self.assertRaisesRegex(PIPError,'EXTERNAL_RECEIPT_AUTHORITY_NOT_INTEGRATED'):
            transition(State.RUNNING,State.SUCCEEDED_ACCREDITED,run=self.run,
                       checkpoint_id='PG-01.C1',inventory=self.inv,outcomes=outcomes,
                       receipt=self.receipt('PG-01.C1'))
        out=transition(State.RUNNING,State.SUCCEEDED_SYNTHETIC,run=self.run,
                       checkpoint_id='PG-01.C1',inventory=self.inv,outcomes=outcomes,
                       receipt=self.receipt('PG-01.C1'))
        self.assertEqual(out.state,State.SUCCEEDED_SYNTHETIC)

    def test_media_1_synthetic_closure_never_accredited(self):
        outcomes={cp:Outcome(State.SUCCEEDED_SYNTHETIC,'SYN','fixture',self.receipt(cp))
                  for cp in self.inv.operational_ids()}
        self.assertEqual(verify_closure(self.inv,self.run,outcomes).state,State.SYNTHETIC_ONLY)

    def test_media_4_api_pin_required_and_tamper(self):
        with self.assertRaisesRegex(PIPError,'EXTERNAL_PIN_REQUIRED'):
            load_inventory(self.path)
        obj=json.loads(self.path.read_text())
        obj['inventory_core']['requires_edges'][3]={'from':'PG-20','requires':'PG-02'}
        core=obj['inventory_core']
        obj['inventory_digest_sha256']=hashlib.sha256(json.dumps(core,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()
        self.path.write_text(json.dumps(obj),encoding='utf8')
        with self.assertRaisesRegex(PIPError,'FULL_FILE_SHA256_MISMATCH'):
            load_inventory(self.path,expected_file_sha256=self.outer)

    def test_media_4_cli_pin_required_and_tamper(self):
        repo=Path(__file__).resolve().parents[1]
        bare=subprocess.run([sys.executable,'-m','pip1_core.cli',str(self.path)],cwd=repo,capture_output=True,text=True)
        self.assertNotEqual(bare.returncode,0)
        self.assertIn('EXTERNAL_PIN_REQUIRED',bare.stderr)
        pinned=subprocess.run([sys.executable,'-m','pip1_core.cli',str(self.path),'--expected-file-sha256',self.outer],cwd=repo,capture_output=True,text=True)
        self.assertEqual(pinned.returncode,0,pinned.stderr)
        wrong=subprocess.run([sys.executable,'-m','pip1_core.cli',str(self.path),'--expected-file-sha256','f'*64],cwd=repo,capture_output=True,text=True)
        self.assertNotEqual(wrong.returncode,0)
        self.assertIn('FULL_FILE_SHA256_MISMATCH',wrong.stderr)

if __name__=='__main__':
    unittest.main()


class D07DeterministicClosure(unittest.TestCase):
    def test_closure_error_is_stable_across_python_hash_seeds(self):
        import os
        root = Path(__file__).resolve().parents[1]
        script = """from test_core import fixture, load
from pip1_core.core import *
i=load(fixture())
r=RunContract('PIP-1','candidate','E','R','X','S',Pins('a'*40,'b'*64,'c'*64,i.digest))
def rc(cp): return Receipt('E','R',cp,'a'*40,r.pins.fingerprint(),'fixture://receipt','e'*64,'PASS')
o={cp: Outcome(State.SUCCEEDED_SYNTHETIC,'PASS','fixture',rc(cp)) for cp in i.operational_ids()}
o['PG-19.C1']=Outcome(State.PENDING,'PENDING','not done')
try: verify_closure(i,r,o)
except PIPError as exc: print(exc.code)
"""
        observed = set()
        for seed in (0, 1, 2, 3, 7, 11, 19, 42, 123, 999):
            result = subprocess.run([sys.executable, '-c', script],
                cwd=root, env={**os.environ, 'PYTHONHASHSEED':str(seed),
                               'PYTHONPATH':str(root)+os.pathsep+str(root/'tests')},
                capture_output=True, text=True, check=True)
            observed.add(result.stdout.strip())
        self.assertEqual(observed, {'DEPENDENCY_UNSATISFIED'})
