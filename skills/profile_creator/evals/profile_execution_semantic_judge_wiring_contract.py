#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
app = (ROOT / "services/profile_runtime_api/profile_runtime_api/app.py").read_text()
engine = (ROOT / "services/profile_runtime_api/profile_runtime_api/engine.py").read_text()
llama = (ROOT / "services/profile_runtime_api/profile_runtime_api/llama.py").read_text()
models = (ROOT / "services/profile_runtime_api/profile_runtime_api/models.py").read_text()
repo = (ROOT / "services/profile_runtime_api/profile_runtime_api/repository.py").read_text()
worker = (ROOT / "services/profile_runtime_api/scripts/hetzner_queue_worker.py").read_text()

assert 'class SemanticJudgeRequest' in models
assert 'canonical_quality' in repo
assert 'def load_canonical_quality' in repo
assert 'def generate_independent_semantic_judge' in llama
assert 'def run_semantic_judge' in engine
assert '"/v1/profile/semantic-judge"' in app
assert 'lf_profile_execution_scope_authority_packet_v1' in worker
assert worker.index('lf_profile_execution_scope_authority_packet_v1') < worker.index('step_id="input_validate"')
assert worker.index('_record_post_model_governance') < worker.index('/v1/profile/semantic-judge')
assert 'PASS_INDEPENDENT_SEMANTIC' in worker
assert 'semantic_model_call_count' in worker
assert 'producer_independence_proven' in worker
assert 'PACK_VALIDATION_HARNESS' not in worker

runtime_files = [app, engine, llama, models, repo, worker]
for content in runtime_files:
    assert "EXEC-M14-SRCR-V06-LIFECYCLE-20260922-001" not in content
    assert "SRCR-LIFECYCLE-DEEP-BLIND-001" not in content

migration_hits = []
for path in (ROOT / "supabase/migrations").glob("*.sql"):
    content = path.read_text(encoding="utf-8")
    if "LF_PROFILE_SEMANTIC_JUDGE_RUNTIME_WIRING_V1" in content:
        migration_hits.append(path)
assert len(migration_hits) == 1, migration_hits

print("PROFILE_EXECUTION_SEMANTIC_JUDGE_WIRING_CONTRACT_PASS")
