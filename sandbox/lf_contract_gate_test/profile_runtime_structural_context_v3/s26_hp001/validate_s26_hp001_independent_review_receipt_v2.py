#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, subprocess, sys, tempfile
from pathlib import Path
REPO='cristhianlujan/claude-persona-lf-patch'
SOURCE_SHA='d8c10954d5a6058ffdde7f4b520efcbabf50d180'
ARTIFACT_TEXT_SHA='bde82803a3116054d9d8b6fc81912fb97582278d'
ARTIFACT_TEXT_PATH='sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_f_exact_materialized_output.review.json'
ARTIFACT_REF='github://cristhianlujan/claude-persona-lf-patch@bde82803a3116054d9d8b6fc81912fb97582278d/sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_f_exact_materialized_output.review.json'
ARTIFACT_SHA256='5d938ada46cdaf809ad38791d3c9b59f8c9f6134d0577cbca2f56ac4bf71c3a7'
GZIP_SHA256='45d32702a97a8d9141d1283cfa3065221434ae2cc9bc19f138bca61010999b2a'
ARTIFACT_DIGEST='decompressed_sha256='+ARTIFACT_SHA256+';gzip_sha256='+GZIP_SHA256
EXPECTED_CASE={'GPT': 'S26-HP001-COLD-GPT-QUALITY-001', 'CLAUDE': 'S26-HP001-COLD-CLAUDE-QUALITY-001'}
EXPECTED_REVIEW_ID={'GPT': 'S26-HP001-COLD-GPT-QUALITY-REVIEW-001', 'CLAUDE': 'S26-HP001-COLD-CLAUDE-QUALITY-REVIEW-001'}
EXPECTED_SOURCE_REFS={'artifact_ref': 'github://cristhianlujan/claude-persona-lf-patch@bde82803a3116054d9d8b6fc81912fb97582278d/sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_f_exact_materialized_output.review.json', 'upstream_worker_contract_ref': 'github://cristhianlujan/claude-persona-lf-patch@d8c10954d5a6058ffdde7f4b520efcbabf50d180/profiles/ui_architect/SKILL.md', 'quality_gate_contract_ref': 'github://cristhianlujan/claude-persona-lf-patch@d8c10954d5a6058ffdde7f4b520efcbabf50d180/profiles/quality_pack/contracts/quality_gate_contract.md', 'lf_quality_controls_ref': 'github://cristhianlujan/claude-persona-lf-patch@d8c10954d5a6058ffdde7f4b520efcbabf50d180/profiles/quality_pack/contracts/lf_quality_controls.md', 'score_rubric_ref': 'github://cristhianlujan/claude-persona-lf-patch@d8c10954d5a6058ffdde7f4b520efcbabf50d180/profiles/quality_pack/judges/quality_pack_score_rubric.md', 'mini_judge_ref': 'github://cristhianlujan/claude-persona-lf-patch@d8c10954d5a6058ffdde7f4b520efcbabf50d180/profiles/quality_pack/judges/quality_pack_mini_judge.md', 'quality_review_schema_ref': 'github://cristhianlujan/claude-persona-lf-patch@d8c10954d5a6058ffdde7f4b520efcbabf50d180/profiles/quality_pack/schemas/quality_review.schema.json'}
EXPECTED_CONTENT_SHA={'profiles/ui_architect/SKILL.md': 'b099944839af79cb97eac76f12ecf8bd38c39ea331224ee335ced32491f411c0', 'profiles/quality_pack/contracts/quality_gate_contract.md': '6c2543a891143dbbec4d0f71eb134da2ac36b4d75fca174b885b4b00429c1553', 'profiles/quality_pack/contracts/lf_quality_controls.md': '069962007fc1cc4320f3ead807973241c710f140e62d6869c2030c11552fe297', 'profiles/quality_pack/judges/quality_pack_score_rubric.md': 'cfb928f5e7d375bcf478666f704d617714be3c7369e8524fc387e78f290e0698', 'profiles/quality_pack/judges/quality_pack_mini_judge.md': 'b6191adfc3895398c5aa480998d130642fc0dd904208d86f884d998254b3e359', 'profiles/quality_pack/schemas/quality_review.schema.json': '26eb79a876be9c7fb8aa699d7f7a549f361b0836d322995f4a5282c1b12443c3', 'profiles/quality_pack/schemas/independent_semantic_review_receipt.schema.json': '8d126b2bf5dde42b88fc3fb334ab4d6ed25f6180497328159c501fcb80db808c', 'profiles/quality_pack/validators/validate_independent_semantic_review.py': '8280788b32749887ca680a7f13a195aa2a5ec454f2dd1c8390b307bc60bf53ba', 'profiles/quality_pack/validators/validate_routing.py': '9a03306077848d6cb9fb68a42078c26ad51d9d5a83f2ac73e823e479e1dea5c1', 'profiles/ui_architect/schemas/ui_production_spec.schema.json': '7f10c952796b045b99069b446f8dd7582d641d3514c25253fd27782045547112', 'profiles/ui_architect/contracts/composer_payload_boundary_v1.md': 'd2b55e3c29c45642ebe18084b23c1ae96064c8c0a6bd8ecb1f5910f2753bb617'}
EVIDENCE_REF_SHA={'github://cristhianlujan/claude-persona-lf-patch@bde82803a3116054d9d8b6fc81912fb97582278d/sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_f_exact_materialized_output.review.json': '5d938ada46cdaf809ad38791d3c9b59f8c9f6134d0577cbca2f56ac4bf71c3a7', 'github://cristhianlujan/claude-persona-lf-patch@d8c10954d5a6058ffdde7f4b520efcbabf50d180/profiles/ui_architect/SKILL.md': 'b099944839af79cb97eac76f12ecf8bd38c39ea331224ee335ced32491f411c0', 'github://cristhianlujan/claude-persona-lf-patch@d8c10954d5a6058ffdde7f4b520efcbabf50d180/profiles/quality_pack/SKILL.md': 'e4083f988a35dbaa65ac795d455d69216ea261b3b4ae39ba791e16c20632db2c', 'github://cristhianlujan/claude-persona-lf-patch@d8c10954d5a6058ffdde7f4b520efcbabf50d180/profiles/quality_pack/contracts/quality_gate_contract.md': '6c2543a891143dbbec4d0f71eb134da2ac36b4d75fca174b885b4b00429c1553','github://cristhianlujan/claude-persona-lf-patch@d8c10954d5a6058ffdde7f4b520efcbabf50d180/profiles/quality_pack/contracts/lf_quality_controls.md': '069962007fc1cc4320f3ead807973241c710f140e62d6869c2030c11552fe297', 'github://cristhianlujan/claude-persona-lf-patch@d8c10954d5a6058ffdde7f4b520efcbabf50d180/profiles/quality_pack/judges/quality_pack_score_rubric.md': 'cfb928f5e7d375bcf478666f704d617714be3c7369e8524fc387e78f290e0698','github://cristhianlujan/claude-persona-lf-patch@d8c10954d5a6058ffdde7f4b520efcbabf50d180/profiles/quality_pack/judges/quality_pack_mini_judge.md': 'b6191adfc3895398c5aa480998d130642fc0dd904208d86f884d998254b3e359', 'github://cristhianlujan/claude-persona-lf-patch@d8c10954d5a6058ffdde7f4b520efcbabf50d180/profiles/quality_pack/schemas/quality_review.schema.json': '26eb79a876be9c7fb8aa699d7f7a549f361b0836d322995f4a5282c1b12443c3','github://cristhianlujan/claude-persona-lf-patch@d8c10954d5a6058ffdde7f4b520efcbabf50d180/profiles/quality_pack/schemas/independent_semantic_review_receipt.schema.json': '8d126b2bf5dde42b88fc3fb334ab4d6ed25f6180497328159c501fcb80db808c','github://cristhianlujan/claude-persona-lf-patch@d8c10954d5a6058ffdde7f4b520efcbabf50d180/profiles/ui_architect/schemas/ui_production_spec.schema.json': '7f10c952796b045b99069b446f8dd7582d641d3514c25253fd27782045547112', 'github://cristhianlujan/claude-persona-lf-patch@d8c10954d5a6058ffdde7f4b520efcbabf50d180/profiles/ui_architect/contracts/composer_payload_boundary_v1.md': 'd2b55e3c29c45642ebe18084b23c1ae96064c8c0a6bd8ecb1f5910f2753bb617','github://cristhianlujan/claude-persona-lf-patch@d8c10954d5a6058ffdde7f4b520efcbabf50d180/profiles/quality_pack/contracts/independent_chat_semantic_review_contract.md': '6f9f978e2dfd0e107e12af88a2fbd81c4e4a4913facd0b09c2051bf867e6e434'}
SCORE_KEYS=['contract_schema_compliance', 'evidence_integrity', 'lf_safety_governance', 'handoff_readiness', 'leakage_scope_control']
EXPECTED_EVIDENCE_REF={'contract_schema_compliance': 'github://cristhianlujan/claude-persona-lf-patch@d8c10954d5a6058ffdde7f4b520efcbabf50d180/profiles/ui_architect/schemas/ui_production_spec.schema.json', 'evidence_integrity': 'github://cristhianlujan/claude-persona-lf-patch@bde82803a3116054d9d8b6fc81912fb97582278d/sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_f_exact_materialized_output.review.json', 'lf_safety_governance': 'github://cristhianlujan/claude-persona-lf-patch@d8c10954d5a6058ffdde7f4b520efcbabf50d180/profiles/quality_pack/contracts/lf_quality_controls.md', 'handoff_readiness': 'github://cristhianlujan/claude-persona-lf-patch@bde82803a3116054d9d8b6fc81912fb97582278d/sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_f_exact_materialized_output.review.json', 'leakage_scope_control': 'github://cristhianlujan/claude-persona-lf-patch@d8c10954d5a6058ffdde7f4b520efcbabf50d180/profiles/ui_architect/contracts/composer_payload_boundary_v1.md'}
ROUTE={'PASS_TO_COMPOSER':('CONTINUE','COMPOSER','GOLDEN_ELIGIBILITY'),'PASS_WITH_RESTRICTIONS':('CONTINUE_WITH_RESTRICTIONS','COMPOSER','GOLDEN_ELIGIBILITY'),'RETURN_TO_WORKER_FOR_SELF_REPAIR':('RETURN_TO_ORCHESTRATOR','PRODUCER_REPAIR','PRODUCER_REPAIR'),'RETURN_TO_ORCHESTRATOR':('RETURN_TO_ORCHESTRATOR','AUTHORITY_OR_CONTEXT_RESOLUTION','AUTHORITY_OR_CONTEXT_RESOLUTION'),'BLOCK_PIPELINE':('BLOCK_PIPELINE','NONE','NONE')}
TOP_KEYS={'receipt_version','execution_mode','semantic_status','review_case_id','reviewer_is_producer','producer_context_available','external_paid_model_used','automated_semantic_judge_implemented','review_completed','source_bundle','quality_review','execution_blockers'}
SOURCE_KEYS={'artifact_ref','artifact_sha_or_digest','upstream_worker_contract_ref','quality_gate_contract_ref','lf_quality_controls_ref','score_rubric_ref','mini_judge_ref','quality_review_schema_ref'}
REVIEW_KEYS={'review_id','reviewed_artifact','verdict','score_breakdown','evidence_map','blocking_codes','repair_actions','remaining_risks','next_gate','routing'}
ROUTING_KEYS={'activation_path','via','pipeline_action','resolution_target'}
SCORE_SET=set(SOCORE_KEYS+['total']); EVIDENCE_KEYS={'criterion','decision_basis','evidence_ref','evidence_sha256'}
def sha256(b): return hashlib.sha256(b).hexdigest()
def git_show(root,commit,path):
 p=subprocess.run(['git','-c',f'safe.directory={root}','show',f'{commit}:{path}'],cwd=root,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 if p.returncode: raise RuntimeError(p.stderr.decode('utf-8','replace')[:300])
 return p.stdout
def validate(root,receipt_path,reviewer):
 e=[]; r=json.loads(receipt_path.read_text(encoding='utf-8'))
 if set(r)!=TOP_KEYS: e.append('TOP_LEVEL_KEYSET_MISMATCH')
 if r.get('review_case_id')!=EXPECTED_CASE[reviewer]: e.append('REVIEW_CASE_ID_MISMATCH')
 s=r.get('source_bundle'); s=s if isinstance(s,dict) else {}
 if set(s)!=SOURCE_KEYS: e.append('SOURCE_BUNDLE_KEYSET_MISMATCH')
 if s.get('artifact_ref')!=ARTIFACT_REF: e.append('ARTIFACT_REF_MISMATCH')
 if s.get('artifact_sha_or_digest')!=ARTIFACT_DIGEST": e.append('ARTIFACT_DIGEST_BINDING_MISMATCH')
 for k,v in EXPECTED_SOURCE_REFS.items():
  if s.get(k)!=v: e.append('SOURCE_REF_MISMATCH:'+k)
 q=r.get('quality_review'); q=q if isinstance(q,dict) else {}
 if set(q)!=REVIEW_KEYS: e.append('QUALITY_REVIEW_KEYSET_MISMATCH')
 if q.get('review_id')!=EXPECTED_REVIEW_ID[reviewer]: e.append('REVIEW_ID_MISMATCH')
 if q.get('reviewed_artifact')!=ARTIFACT_REF: e.append('REVIEWED_ARTIFACT_MISMATCH')
 sc=q.get('score_breakdown'); sc=sc if isinstance(sc,dict) else {}
 if set(sc)!=SCORE_SET: e.append('SCORE_KEYSET_MISMATCH')
 rt=q.get('routing'); rt=rt if isinstance(rt,dict) else {}
 if set(rt)!=ROUTING_KEYS: e.append('ROUTING_KEYSET_MISMATCH')
 if rt.get('activation_path')!='DIRECT': e.append('ACTIVATION_PATH_MUST_BE_DIRECT')
 verdict=q.get('verdict')
 if verdict in ROUTE:
  pa,target,next_gate=ROUTE[verdict]
  if rt.get('via')!='ORCHESTRATOR' or rt.get('pipeline_action')!=pa or rt.get('resolution_target')!=target: e.append('ROUTING_BINDING_MISMATCH')
  if q.get('next_gate')!=next_gate: e.append('NEXT_GATE_BINDING_MISMATCH')
 em=q.get('evidence_map')
 if not isinstance(em,list) or len(em)!=5: e.append('EVIDENCE_MAP_MUST_HAVE_EXACTLY_5_ITEMS')
 else:
  for i,(item,criterion) in enumerate(zip(em,SCORE_KEYS)):
   if not isinstance(item,dict) or set(item)!=EVIDENCE_KEYS: e.append(f'EVIDENCE_ITEM_KEYSET_MISMATCH:{i}'); continue
   if item.get('criterion')!=criterion: e.append(f'EVIDENCE_CRITERION_ORDER_MISMATCH:{i}')
   if not isinstance(item.get('decision_basis'),str) or not item['decision_basis'].strip(): e.append(f'EVIDENCE_DECISION_BASIS_REQUIRED:{i}')
   ref=item.get('evidence_ref'); dig=item.get('evidence_sha256')
   if ref!=EXPECTED_EVIDENCE_REF[criterion]: e.append(f'EVIDENCE_REF_BINDING_MISMATCH:{criterion}')
   if ref not in EVIDENCE_REF_SHA or dig!=EVIDENCE_REF_SHA.get(ref): e.append(f'EVIDENCE_SHA_BINDING_MISMATCH:{criterion}')
 if sha256(git_show(root,ARTIFACT_TEXT_SHA,ARTIFACT_TEXT_PATH))!=ARTIFACT_SHA256: e.append('IMMUTABLE_ARTIFACT_SHA_MISMATCH')
 for path,dig in EXPECTED_CONTENT_SHA.items():
  try: got=sha256(git_show(root,SOURCE_SHA,path))
  except Exception: e.append('IMMUTABLE_SOURCE_UNRESOLVED:'+path); continue
  if got!=dig: e.append('IMMUTABLE_SOURCE_SHA_MISMATCH:'+path)
 with tempfile.TemporaryDirectory(prefix='s26_hp001_v2_') as td:
  td=Path(td); iv=td/'iv.py'; rv=td/'rv.py'; qs=td/'q.json'; qp=td/'quality.json'
  iv.write_bytes(git_show(root,SOURCE_SHA,'profiles/quality_pack/validators/validate_independent_semantic_review.py'))
  rv.write_bytes(git_show(root,SOURCE_SHA,'profiles/quality_pack/validators/validate_routing.py'))
  qs.write_bytes(git_show(root,SOURCE_SHA,'profiles/quality_pack/schemas/quality_review.schema.json'))
  p=subprocess.run([sys.executable,str(iv),str(receipt_path)],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  if p.returncode: e.append('OFFICIAL_INDEPENDENT_RECEIPT_VALIDATOR_FAILED')
  qp.write_text(json.dumps(q,ensure_ascii=False),encoding='utf-8')
  p=subprocess.run([sys.executable,str(rv),str(qp)],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  if p.returncode: e.append('OFFICIAL_ROUTING_VALIDATOR_FAILED')
  try:
   import jsonschema; jsonschema.validate(q,json.loads(qs.read_text()))
  except Exception as x: e.append('QUALITY_REVIEW_SCHEMA_FAILED:'+type(x).__name__)
 return sorted(set(e))
def main():
 ap=argparse.ArgumentParser(); ap.add_argument('--repo-root',required=True); ap.add_argument('--reviewer',choices=['GPT','CLAUDE'],required=True); ap.add_argument('receipt'); a=ap.parse_args()
 errors=validate(Path(a.repo_root).resolve(),Path(a.receipt).resolve(),a.reviewer)
 print(json.dumps({'valid':not errors,'reviewer':a.reviewer,'artifact_sha256':ARTIFACT_SHA256,'errors':errors},indent=2)); return 0 if not errors else 1
if __name__=='__main__': raise SystemExit(main())
