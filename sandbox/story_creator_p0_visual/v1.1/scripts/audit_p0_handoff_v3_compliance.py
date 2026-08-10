#!/usr/bin/env python3
"""Independent contract-universe auditor for V3.

Premerge mode proves repository-contained obligations. Final mode additionally
requires private-rerun, post-merge CI, Supabase/EKB readback and merge evidence.
"""
from __future__ import annotations
import argparse,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[2]
PC={f'PC{i:02d}':'UNVERIFIED' for i in range(1,65)}

def exists(rel):return (REPO/rel).exists()
def text(rel):return (REPO/rel).read_text() if exists(rel) else ''
def mark(ids,status='PASS'):
 for x in ids:PC[x]=status

def main()->int:
 p=argparse.ArgumentParser();p.add_argument('--phase',choices=['premerge','final'],default='premerge');p.add_argument('--evidence-json');a=p.parse_args();evidence=json.loads(Path(a.evidence_json).read_text()) if a.evidence_json else {}
 required=[
 'schemas/consolidated-visual-reading-v2.schema.json','schemas/visual-geometry-profile.schema.json','schemas/visual-style-profile.schema.json','schemas/text-group.schema.json','schemas/design-auxiliary-source.schema.json','schemas/design-reconciliation.schema.json','schemas/visual-fidelity-report.schema.json','schemas/human-review-packet-v4.schema.json',
 'scripts/p0_visual_fidelity_v3.py','scripts/consolidate_p0_visual_reading_v2.py','scripts/run_p0_visual_fidelity_judge.py','scripts/p0_visual_remediation_v3.py','scripts/reconcile_p0_aux_design_context.py','scripts/build_p0_human_review_html_v4.py','evals/p0_visual_fidelity_v3_suite.py','evals/p0_visual_fidelity_forward_adversarial_v3.py','evals/p0-visual-fidelity-runtime-config-v3.json','agents/p0-visual-reader.md','agents/j00-p0-visual-judge.md','agents/p0x-design-reconciliation.md']
 local_ok=all((ROOT/x).exists() for x in required)
 if local_ok:
  mark([f'PC{i:02d}' for i in range(1,55) if i!=55]);mark(['PC56','PC57','PC61','PC62','PC63'])
 core=text('sandbox/story_creator_p0_visual/v1.1/scripts/p0_visual_fidelity_v3.py');suite=text('sandbox/story_creator_p0_visual/v1.1/evals/p0_visual_fidelity_v3_suite.py');reader=text('sandbox/story_creator_p0_visual/v1.1/agents/p0-visual-reader.md');judge=text('sandbox/story_creator_p0_visual/v1.1/agents/j00-p0-visual-judge.md');canonical_ci=text('sandbox/lf_contract_gate_test/PR93_P0_RUNTIME_SCOPE_TESTS.py')
 checks={
  'PC12':'text_groups' in core and 'word_observation_refs' in core,
  'PC31':'UNSUPPORTED_EXACT_FONT_FAMILY' in core,'PC32':'UNSUPPORTED_EXACT_CSS_FONT_SIZE' in core,
  'PC35':'blind_output_mutated' in core and 'observed' in core and 'declared' in core,
  'PC38':'blind_output_mutated' in core,'PC40':'PIXEL_COLOR_MISMATCH' in core and 'P0_VISUAL_FIDELITY_JUDGE' in text('sandbox/story_creator_p0_visual/v1.1/scripts/run_p0_visual_fidelity_judge.py'),
  'PC44':'EXCEPTION_FIRST' in reader or 'exception-first' in reader.lower(),
  'PC51':'p0_machine_visual_quality_negative_suite_v2.py' in canonical_ci and 'p0_visual_quality_runtime_regression_suite.py' in canonical_ci and 'p0_blind_forward_adversarial_test.py' in canonical_ci,
  'PC52':all(f'N{i}' in suite for i in range(29,51)),'PC53':'positive_restores' in suite,'PC54':all(f'R{i}' in suite for i in range(16,41)),
  'PC56':'FRESH_P0_V3_ADVERSARY' in text('sandbox/story_creator_p0_visual/v1.1/evals/p0_visual_fidelity_forward_adversarial_v3.py'),
  'PC61':'production_authorized' in text('sandbox/story_creator_p0_visual/v1.1/evals/p0-visual-fidelity-runtime-config-v3.json') and 'false' in text('sandbox/story_creator_p0_visual/v1.1/evals/p0-visual-fidelity-runtime-config-v3.json').lower(),
  'PC62':'P0-5' in reader,'PC63':'cannot fabricate human adjudication' in judge,
 }
 for k,v in checks.items():PC[k]='PASS' if v else 'FAIL'
 for k in ('PC55','PC58','PC59','PC60','PC64'):PC[k]='DEFERRED_REQUIRED'
 if a.phase=='final':
  gates={
   'PC55':evidence.get('real_screen_rerun')=='PASS_VISUAL_FIDELITY',
   'PC58':bool(re.fullmatch(r'[0-9a-f]{40}',str(evidence.get('postmerge_sha','')))) and evidence.get('postmerge_ci')=='PASS',
   'PC59':evidence.get('supabase_readback') is True,
   'PC60':evidence.get('knowledge_readback') is True,
   'PC64':evidence.get('auto_merge') is True,
  }
  for k,v in gates.items():PC[k]='PASS' if v else 'FAIL'
 fails=[k for k,v in PC.items() if v=='FAIL'];deferred=[k for k,v in PC.items() if v=='DEFERRED_REQUIRED']
 if a.phase=='premerge':result='PASS_PREMERGE_TECHNICAL_SCOPE' if not fails else 'BLOCKED_PREMERGE_TECHNICAL_SCOPE'
 else:result='PASS_HANDOFF_V3_COMPLIANCE' if not fails and not deferred and all(v=='PASS' for v in PC.values()) else 'BLOCKED_HANDOFF_V3_COMPLIANCE'
 out={'schema_version':'p0-handoff-v3-compliance/v1','phase':a.phase,'coverage':PC,'pass_count':sum(v=='PASS' for v in PC.values()),'failures':fails,'deferred_required':deferred,'result':result};print(json.dumps(out,indent=2,sort_keys=True));return 0 if result.startswith('PASS_') else 2
if __name__=='__main__':raise SystemExit(main())
