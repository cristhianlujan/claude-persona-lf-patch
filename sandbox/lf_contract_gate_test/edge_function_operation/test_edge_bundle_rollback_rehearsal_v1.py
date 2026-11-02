"""Adversarial unit tests of the exact-scope offline rollback rehearsal."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from edge_bundle_rollback_rehearsal_v1 import (
    ROLLBACK_REF, RUNTIME_FILES, TARGET_SLUG, CanaryBlocked,
    apply_bundle, rehearse, run, sha256, state,
    LEGACY_DENO_TYPES_IMPORT, CURRENT_DENO_TYPES_COMMENT,
)

OLD = {
    "index.ts": b'import { createHandler } from "./caller.ts";\n',
    "caller.ts": b"export const handler = 'old';\n",
}
NEW = {
    **OLD,
    "caller.ts": b'import { executeCp2 } from "./cp2_edge_bridge.ts";\nexport const handler = "new";\n',
    "cp2_edge_bridge.ts": b'export const executeCp2 = () => null;\n',
}
HEAD = "a" * 40
# Same executable entrypoint, exact reviewed removal of a type-only import.
LEGACY_INDEX = LEGACY_DENO_TYPES_IMPORT + OLD["index.ts"]
CURRENT_INDEX = CURRENT_DENO_TYPES_COMMENT + OLD["index.ts"]

def get_live(token):
    return {
        "result": "EDGE_MANAGEMENT_READ_PASS",
        "target": TARGET_SLUG,
        "version": 23,
        "method": "GET",
        "deployed": False,
    }

def read_repo(ref, name):
    if ref == HEAD and name in NEW:
        return NEW[name]
    if ref == ROLLBACK_REF and name in OLD:
        return OLD[name]
    raise AssertionError("UNEXPECTED_GIT_REF_OR_PATH")

class RollbackRehearsalTests(unittest.TestCase):
    def test_local_forward_repeat_and_rollback_repeat(self):
        x = rehearse(NEW, OLD)
        self.assertEqual(x["local_file_rehearsal"], "VERIFIED")
        self.assertEqual(x["local_file_idempotency"], "VERIFIED")
        self.assertEqual(x["local_forward_repeat_changes"], 0)
        self.assertEqual(x["local_rollback_repeat_changes"], 0)
        self.assertEqual(set(x["source_file_sha256"]), set(RUNTIME_FILES))
        self.assertEqual(set(x["rollback_file_sha256"]), set(OLD))

    def test_live_read_only_before_and_after(self):
        invocations = []
        def live(token):
            invocations.append("GET")
            return get_live(token)
        with patch.dict("os.environ", {
            "GITHUB_SHA": HEAD,
            "GITHUB_RUN_ID": "TEST123",
            "SUPABASE_ACCESS_TOKEN": "synthetic-no-valid-credential",
        }):
            x = run(read=live, source_reader=read_repo, git_head=lambda: HEAD)
        self.assertEqual(invocations, ["GET", "GET"])
        self.assertEqual(x["exact_main_sha"], HEAD)
        self.assertEqual(x["live_edge_version_before"], 23)
        self.assertEqual(x["live_edge_version_after"], 23)
        self.assertEqual(x["github_run_id"], "TEST123")
        self.assertFalse(x["provider_deployment_executed"])
        self.assertFalse(x["provider_rollback_executed"])
        self.assertFalse(x["provider_idempotency_executed"])
        self.assertEqual(x["r17_verdict"], "PARTIAL_NOT_AUTHORIZED")
        self.assertEqual(x["cp2_runs_started"], 0)
        self.assertNotIn("synthetic-no-valid-credential", str(x))

    def test_missing_bridge_rejected(self):
        with self.assertRaisesRegex(CanaryBlocked, "R17_BUNDLE_SCOPE_OR_ROLLBACK_MISMATCH"):
            rehearse({k: v for k, v in NEW.items() if k != "cp2_edge_bridge.ts"}, OLD)

    def test_other_file_rejected(self):
        with self.assertRaisesRegex(CanaryBlocked, "R17_BUNDLE_SCOPE_OR_ROLLBACK_MISMATCH"):
            rehearse({**NEW, "other.ts": b"unsafe"}, OLD)

    def test_modified_entrypoint_rejected(self):
        with self.assertRaisesRegex(CanaryBlocked, "R17_INDEX_ENTRYPOINT_DRIFT"):
            rehearse({**NEW, "index.ts": NEW["index.ts"] + b"// unexpected change\n"}, OLD)

    def test_exact_types_only_entrypoint_change_allowed(self):
        receipt = rehearse({**NEW, "index.ts": CURRENT_INDEX}, {**OLD, "index.ts": LEGACY_INDEX})
        self.assertEqual(receipt["local_file_rehearsal"], "VERIFIED")
        self.assertEqual(receipt["local_file_idempotency"], "VERIFIED")
        self.assertEqual(receipt["local_forward_repeat_changes"], 0)
        self.assertEqual(receipt["local_rollback_repeat_changes"], 0)
        self.assertNotEqual(receipt["source_file_sha256"]["index.ts"], receipt["rollback_file_sha256"]["index.ts"])

    def test_types_only_exception_rejects_executable_entrypoint_change(self):
        old = {**OLD, "index.ts": LEGACY_INDEX}
        for changed in (
            CURRENT_INDEX + b"\nDeno.exit(1);\n",
            CURRENT_INDEX.replace(b"createHandler", b"createHandlerEvil"),
            CURRENT_INDEX.replace(b"\n", b"\n// changed other part\n", 1),
            CURRENT_INDEX.replace(CURRENT_DENO_TYPES_COMMENT, b"// near but not exact\n"),
            LEGACY_INDEX.replace(LEGACY_DENO_TYPES_IMPORT, b'import "./evil.ts";\n'),
        ):
            with self.subTest(changed=changed[:70]):
                with self.assertRaisesRegex(CanaryBlocked, "R17_INDEX_ENTRYPOINT_DRIFT"):
                    rehearse({**NEW, "index.ts": changed}, old)

    def test_types_only_exception_rejects_modified_baseline_import(self):
        current = {**NEW, "index.ts": CURRENT_INDEX}
        mutated = LEGACY_INDEX.replace(LEGACY_DENO_TYPES_IMPORT, b'import "./evil.ts";\n')
        with self.assertRaisesRegex(CanaryBlocked, "R17_INDEX_ENTRYPOINT_DRIFT"):
            rehearse(current, {**OLD, "index.ts": mutated})

    def test_missing_bridge_import_rejected(self):
        with self.assertRaisesRegex(CanaryBlocked, "R17_BRIDGE_IMPORT_MISSING"):
            rehearse({**NEW, "caller.ts": b"export const x = 1;"}, OLD)

    def test_missing_caller_import_rejected(self):
        with self.assertRaisesRegex(CanaryBlocked, "R17_CALLER_IMPORT_MISSING"):
            rehearse({**NEW, "index.ts": b'export const x = 2;'}, OLD)

    def test_no_new_caller_rejected(self):
        with self.assertRaisesRegex(CanaryBlocked, "R17_NO_NEW_CALLER_DELTA"):
            rehearse({**NEW, "caller.ts": OLD["caller.ts"]}, OLD)

    def test_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            out = directory / "other"
            out.write_bytes(b"external")
            (directory / "caller.ts").symlink_to(out)
            with self.assertRaisesRegex(CanaryBlocked, "R17_UNSAFE_TEMP_PATH"):
                apply_bundle(directory, NEW)

    def test_reject_unknown_bundle_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(CanaryBlocked, "R17_BUNDLE_TARGET_ESCAPE"):
                apply_bundle(Path(tmp), {"elsewhere": b"not allowed"})

    def test_no_modification_for_repeated_stage(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            self.assertGreater(apply_bundle(directory, NEW), 0)
            before = state(directory)
            self.assertEqual(apply_bundle(directory, NEW), 0)
            self.assertEqual(before, state(directory))

    def test_provider_version_changed_blocks(self):
        count = [0]
        def drifting(token):
            count[0] += 1
            return {**get_live(token), "version": 23 if count[0] == 1 else 24}
        with self.assertRaisesRegex(CanaryBlocked, "R17_LIVE_VERSION_CHANGED_DURING_REHEARSAL"):
            run(read=drifting, source_reader=read_repo, git_head=lambda: HEAD)

    def test_provider_missing_denied(self):
        def bad(token):
            raise CanaryBlocked("EDGE_MANAGEMENT_CREDENTIAL_DENIED_403")
        with self.assertRaisesRegex(CanaryBlocked, "CREDENTIAL_DENIED"):
            run(read=bad, source_reader=read_repo, git_head=lambda: HEAD)

    def test_rollback_mutated_copy_does_not_match_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            apply_bundle(directory, OLD)
            prior = state(directory)
            (directory / "caller.ts").write_bytes(b"tampered")
            self.assertNotEqual(state(directory), prior)
            apply_bundle(directory, OLD)
            self.assertEqual(state(directory), prior)

if __name__ == "__main__":
    unittest.main()
