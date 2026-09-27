#!/usr/bin/env python3
from pathlib import Path
import hashlib
import subprocess

SOURCE=Path(".github/workflows/lf-contract-check.yml")
TARGET=Path("sandbox/lf_contract_gate_test/_cutover_payload/lf-contract-check.yml")
EXPECTED_SOURCE_BLOB="f0466a8641361147ed9404ca886e2d2249f03d56"
EXPECTED_TARGET_BLOB="132ffecc2f6fc5f789669db723b347552daecb8e"
EXPECTED_TARGET_SHA256="3ec6b7bf58ffb65939088477f407013caf7c0dd1a227107d7a9b718a7c976ead"
START="      - name: Prepare LF migration source parity frozen inputs\n"
END="      - name: Enforce Input Governance migration source parity\n"
OLD_CMD='            --command-json \'{"argv":["python3","sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_lane_workflow_integration.py"],"source_path":"sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_lane_workflow_integration.py","critical":true}\' \\\n'
NEW_CMD='            --command-json \'{"argv":["python3","sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_lane_workflow_integration_v2.py","--legacy-test","sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_lane_workflow_integration.py"],"source_path":"sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_lane_workflow_integration_v2.py","critical":true}\' \\\n'
NEW_BLOCK='      - name: Execute Migration Source Parity through canonical owner carrier\n        if: contains(fromJSON(steps.feedback_tier.outputs.lf_contract_controls_json), \'MIGRATION_SOURCE_PARITY\')\n        env:\n          LF_SUPABASE_DB_PASSWORD: ${{ secrets.LF_SUPABASE_DB_PASSWORD }}\n          SUPABASE_PROJECT_ID: mhwmirqcgxxukpctffuv\n          SUPABASE_POOLER_HOST: aws-1-us-east-1.pooler.supabase.com\n          GITHUB_TOKEN: ${{ github.token }}\n          GITHUB_REPOSITORY: ${{ github.repository }}\n          LF_MIGRATION_BASE_SHA: ${{ github.event_name == \'pull_request\' && github.event.pull_request.base.sha || github.sha }}\n          LF_MIGRATION_HEAD_SHA: ${{ github.event_name == \'pull_request\' && github.event.pull_request.head.sha || github.sha }}\n          LF_MIGRATION_BASE_REF: ${{ github.event_name == \'pull_request\' && github.event.pull_request.base.ref || github.ref_name }}\n          LF_MIGRATION_EVENT_NAME: ${{ github.event_name }}\n        shell: bash\n        run: |\n          set -euo pipefail\n          rm -rf .lf_gate_diagnostics/lf_contract_check/migration_source_parity\n          python3 sandbox/lf_contract_gate_test/gate_check_observability/run_gate_checks_v1.py \\\n            --gate-id LF_CONTRACT_CHECK_MIGRATION_SOURCE_PARITY \\\n            --step-id migration_source_parity \\\n            --mode COLLECT_ALL \\\n            --command-json "{\\"argv\\":[\\"python3\\",\\"sandbox/lf_contract_gate_test/migration_source_parity/run_migration_source_parity_flow_v1.py\\",\\"--repo-root\\",\\".\\",\\"--base-sha\\",\\"${LF_MIGRATION_BASE_SHA}\\",\\"--head-sha\\",\\"${LF_MIGRATION_HEAD_SHA}\\",\\"--base-ref\\",\\"${LF_MIGRATION_BASE_REF}\\",\\"--event-name\\",\\"${LF_MIGRATION_EVENT_NAME}\\",\\"--output-dir\\",\\".lf_gate_diagnostics/lf_contract_check/migration_source_parity/owner\\"],\\"source_path\\":\\"sandbox/lf_contract_gate_test/migration_source_parity/run_migration_source_parity_flow_v1.py\\",\\"critical\\":true}" \\\n            --artifact-dir .lf_gate_diagnostics/lf_contract_check/migration_source_parity \\\n            --artifact-name lf_gate_error_v1.json \\\n            --check-prefix MSP \\\n            --owner MIGRATION_SOURCE_PARITY \\\n            --next-action FIX_MIGRATION_SOURCE_PARITY_AND_RERUN_LF_CONTRACT_CHECK \\\n            --downstream-impact MIGRATION_SOURCE_PARITY \\\n            --downstream-impact GOVERNANCE\n          test -s .lf_gate_diagnostics/lf_contract_check/migration_source_parity/owner/run-summary.json\n          python3 - <<\'PY\'\n          import json\n          from pathlib import Path\n          summary = json.loads(\n              Path(".lf_gate_diagnostics/lf_contract_check/migration_source_parity/owner/run-summary.json")\n              .read_text(encoding="utf-8")\n          )\n          if summary.get("status") != "PASS":\n              raise SystemExit("FAIL_MIGRATION_SOURCE_PARITY_OWNER_CARRIER_STATUS")\n          if summary.get("functional_core_duplicated") is not False:\n              raise SystemExit("FAIL_MIGRATION_SOURCE_PARITY_OWNER_CARRIER_DUPLICATED_CORE")\n          print("PASS_MIGRATION_SOURCE_PARITY_OWNER_CARRIER_READBACK")\n          PY\n\n'

def blob_hash(data: bytes)->str:
    return hashlib.sha1(f"blob {len(data)}\0".encode()+data).hexdigest()

data=SOURCE.read_bytes()
if blob_hash(data)!=EXPECTED_SOURCE_BLOB:
    raise SystemExit(f"FAIL_SOURCE_BLOB expected={EXPECTED_SOURCE_BLOB} actual={blob_hash(data)}")
text=data.decode("utf-8")
if text.count(START)!=1 or text.count(END)!=1:
    raise SystemExit("FAIL_MIGRATION_BLOCK_MARKERS")
s=text.index(START); e=text.index(END,s)
text=text[:s]+NEW_BLOCK+text[e:]
if text.count(OLD_CMD)!=1:
    raise SystemExit(f"FAIL_OLD_INTEGRATION_COMMAND_COUNT count={text.count(OLD_CMD)}")
text=text.replace(OLD_CMD,NEW_CMD,1)
out=text.encode("utf-8")
actual_blob=blob_hash(out)
actual_sha256=hashlib.sha256(out).hexdigest()
if actual_blob!=EXPECTED_TARGET_BLOB or actual_sha256!=EXPECTED_TARGET_SHA256:
    raise SystemExit(f"FAIL_TARGET_DIGEST blob={actual_blob} sha256={actual_sha256}")
TARGET.parent.mkdir(parents=True,exist_ok=True)
TARGET.write_bytes(out)
print(f"PASS_BUILD_MIGRATION_PARITY_CUTOVER blob={actual_blob} sha256={actual_sha256} bytes={len(out)}")
