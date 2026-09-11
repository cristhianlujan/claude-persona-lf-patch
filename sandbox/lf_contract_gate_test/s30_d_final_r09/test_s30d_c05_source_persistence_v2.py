#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json, sys, unittest
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
sys.path.insert(0,str(ROOT/'sandbox/lf_contract_gate_test'))
import migration_transport_normalization as transport
PARITY=ROOT/'sandbox/lf_contract_gate_test/lf_migration_source_parity.py'
class T(unittest.TestCase):
 def setUp(self): self.r=json.loads((HERE/'c05_source_persistence_closeout_v2.json').read_text())
 def test_base_is_current_main_candidate_and_no_merge_claim(self):
  self.assertEqual(self.r['base_main_sha'],'b5f1c11cd37acd2c53bf63c66d9f96abf96c756e')
  self.assertFalse(self.r['current_candidate_actions']['main_merge_authorized'])
 def test_s26_shared_classifier_slice_is_stable_but_s26_overall_not_closed(self):
  s=self.r['s26_shared_classifier_dependency']
  self.assertTrue(s['byte_identical_core_baseline']); self.assertFalse(s['later_s26_changes_are_classifier_changes'])
  self.assertFalse(s['s26_overall_gate_f_closed']); self.assertEqual(s['blocker_relevance_to_ci009_strategy_family'],'UNRELATED')
 def test_generic_strategy_family_is_not_c05_exact_name_patch(self):
  text=PARITY.read_text(); self.assertIn('STRATEGY_MIGRATION_RE',text); self.assertNotIn('S30_C05_MANAGED_EXACT_NAMES',text); self.assertIn('s31_future_strategy_contract_v1',text)
 def test_canonical_migration_sources_match_remote_ledger_normalized_hashes(self):
  for m in self.r['canonical_migrations']:
   p=ROOT/m['path']; sql=p.read_text()
   self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(),m['sha256'])
   self.assertEqual(transport.direct_source_hash(sql),m['direct_source_sha256'])
   self.assertEqual(m['direct_source_sha256'],m['remote_ledger_canonical_sha256'])
 def test_primary_submitted_candidate_remains_preserved_separately(self):
  live=json.loads((HERE/'c05_dynamic_fire_test_receipt_v1.json').read_text()); m=live['migration']['primary']
  submitted=ROOT/m['repo_path']; canonical=ROOT/m['canonical_repo_path']
  self.assertEqual(hashlib.sha256(submitted.read_bytes()).hexdigest(),m['submitted_candidate_sha256'])
  self.assertEqual(hashlib.sha256(canonical.read_bytes()).hexdigest(),m['canonical_repo_raw_sha256'])
  self.assertNotEqual(submitted.read_bytes(),canonical.read_bytes())
  self.assertEqual(transport.direct_source_hash(canonical.read_text()),m['remote_ledger_canonical_sha256'])
 def test_closeout_live_evidence_is_exact_and_nine_of_nine(self):
  e=self.r['live_c05_evidence']
  for key in ('dynamic_closeout_manifest','dynamic_fire_receipt','final_schema_readback'):
   p=ROOT/e[key]['path']; self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(),e[key]['sha256'])
  self.assertEqual(e['dynamic_fire_receipt']['cases_pass'],'9/9'); self.assertFalse(e['temporal_overlap_empirically_proven']); self.assertFalse(e['external_exactly_once_claimed'])
 def test_no_new_runtime_or_supabase_write_in_source_persistence_candidate(self):
  a=self.r['current_candidate_actions']
  for k in ('supabase_write','ddl_replayed','runtime_activated','scheduler_changed','s26_mutated','operation_registry_changed','production_changed'): self.assertFalse(a[k],k)
  self.assertFalse(self.r['source_parity_reconciliation']['ddl_replayed']); self.assertFalse(self.r['source_parity_reconciliation']['supabase_write'])
if __name__=='__main__':
 r=unittest.main(verbosity=2,exit=False).result
 print(f"S30_C05_SOURCE_PERSISTENCE_V2_TESTS={r.testsRun} RESULT={'PASS' if r.wasSuccessful() else 'FAIL'}")
 raise SystemExit(0 if r.wasSuccessful() else 1)
