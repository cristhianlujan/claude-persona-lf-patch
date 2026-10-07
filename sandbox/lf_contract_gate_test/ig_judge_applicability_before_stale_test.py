from pathlib import Path

workflow = (Path(__file__).resolve().parents[2] / ".github" / "workflows" / "pase-merge-gate.yml").read_text(encoding="utf-8")

job = workflow.split("  ig-runtime-candidate-judge:", 1)[1]
classify = job.split("      - name: Classify exact IG judge request without executing PR code", 1)[1]
classify = classify.split("      - name: Execute rollback-only independent IG flow judge", 1)[0]

fork_guard = classify.index('if [ "$HEAD_REPOSITORY" != "$REPOSITORY" ]; then')
fetch_head = classify.index('git fetch --no-tags --depth=200 origin "$HEAD_SHA"')
request_path = classify.index("REQUEST_PATH='sandbox/ig_cv/n9_requests/request.json'")
scope_check = classify.index('git diff --quiet "$BASE_SHA" "$HEAD_SHA" -- "$REQUEST_PATH"')
not_applicable = classify.index('PASS_IG_N9_NOT_APPLICABLE')
current_main = classify.index('CURRENT_MAIN_SHA="$(git ls-remote origin refs/heads/main')
stale_gate = classify.index('BLOCK_IG_N9_STALE_BASE')
request_read = classify.index('git show "$HEAD_SHA:$REQUEST_PATH"')

assert fork_guard < fetch_head < request_path < scope_check < not_applicable < current_main < stale_gate < request_read
assert 'IG_N9_APPLICABLE=false' in classify
assert 'IG_N9_APPLICABLE=true' in classify

print("PASS_IG_JUDGE_APPLICABILITY_BEFORE_STALE=9/9")
