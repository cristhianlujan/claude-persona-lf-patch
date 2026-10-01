import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from profile_runtime_api.repository import RepositoryError
from profile_runtime_api.task_runtime_binding import TaskRuntimeBindingAdapter


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def canonical(value) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


class TaskRuntimeBindingAdapterTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.embedded = self.root / "skills/story/perfiles"
        self.embedded.mkdir(parents=True)
        files = {
            "skills/story/perfiles/PERFIL_X.md": b"# Perfil X\nrole: TEST\n",
            "skills/story/agents/x.md": b"# Agent X\n",
            "skills/story/schemas/out.schema.json": b'{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","required":["ok"],"properties":{"ok":{"type":"boolean"}},"additionalProperties":false}\n',
            "skills/story/scripts/validator.py": b"def validate(payload):\n    return [] if payload.get('ok') is True else ['NOT_OK']\n",
            "skills/story/judges/jx.yaml": b"judge_code: JX\nworker_must_not_execute_own_judge: true\n",
        }
        self.rows = []
        for ref, raw in files.items():
            path = self.root / ref
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
            self.rows.append({"path": ref, "sha256": sha(raw)})
        self.adapter = TaskRuntimeBindingAdapter(self.root, max_prompt_chars=1000)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def resolution(self, *, invocation: str = "PYTHON_CALLABLE") -> dict:
        rows = {row["path"]: row for row in self.rows}
        binding = {
            "step_id": "STEP_X",
            "worker_role": "ROLE_X",
            "profile_code": "PERFIL-X",
            "profile_slug": "x",
            "source_mode": "EMBEDDED_SKILL_PROFILE",
            "source_root": "skills/story",
            "source_revision": "a" * 40,
            "source_refs": sorted(self.rows, key=lambda item: item["path"]),
            "runtime_schema": {
                "ref": "skills/story/schemas/out.schema.json",
                "sha256": rows["skills/story/schemas/out.schema.json"]["sha256"],
                "selection_mode": "EXACT_REF",
            },
            "deterministic_validator": {
                "ref": "skills/story/scripts/validator.py",
                "sha256": rows["skills/story/scripts/validator.py"]["sha256"],
                "invocation": invocation,
                **({"callable": "validate"} if invocation == "PYTHON_CALLABLE" else {}),
            },
            "judge_binding": {
                "judge_code": "JX",
                "ref": "skills/story/judges/jx.yaml",
                "sha256": rows["skills/story/judges/jx.yaml"]["sha256"],
                "worker_must_not_execute_own_judge": True,
            },
            "model_context": {
                "source_refs": [
                    "skills/story/perfiles/PERFIL_X.md",
                    "skills/story/agents/x.md",
                ],
                "max_chars": 100,
            },
            "authority_refs": [
                {"ref": "asset://PERFIL-X", "revision": "1", "digest": "f" * 64}
            ],
            "worker_binding_digest": "b" * 64,
        }
        return {
            "schema_version": "LF_PROFILE_TASK_RUNTIME_BINDING_V1",
            "status": "RESOLVED",
            "decision": "TASK_RUNTIME_BINDING_RESOLVED",
            "binding": binding,
            "binding_digest": hashlib.sha256(canonical(binding).encode("utf-8")).hexdigest(),
        }

    def test_embedded_binding_materializes_exact_bytes(self) -> None:
        materialized = self.adapter.materialize(self.resolution())
        self.assertEqual(materialized.source_mode, "EMBEDDED_SKILL_PROFILE")
        self.assertEqual(materialized.profile_code, "PERFIL-X")
        self.assertEqual(materialized.schema.mode, "TASK_BOUND_EXACT_REF")
        self.assertEqual(materialized.schema.source_refs, ("skills/story/schemas/out.schema.json",))
        self.assertEqual(materialized.validator.invocation, "PYTHON_CALLABLE")
        self.assertEqual(materialized.judge.judge_code, "JX")
        self.assertEqual(
            [item["ref"] for item in materialized.profile_sources],
            ["skills/story/perfiles/PERFIL_X.md", "skills/story/agents/x.md"],
        )
        module, callable_name = self.adapter.load_callable_validator(materialized)
        self.assertEqual(callable_name, "validate")
        self.assertEqual(getattr(module, callable_name)({"ok": True}), [])
        self.assertEqual(getattr(module, callable_name)({"ok": False}), ["NOT_OK"])

    def test_cli_descriptor_is_materialized_but_not_loaded_as_callable(self) -> None:
        materialized = self.adapter.materialize(self.resolution(invocation="CLI"))
        self.assertEqual(materialized.validator.invocation, "CLI")
        with self.assertRaisesRegex(RepositoryError, "PROFILE_TASK_BINDING_VALIDATOR_NOT_CALLABLE"):
            self.adapter.load_callable_validator(materialized)

    def test_digest_mismatch_blocks(self) -> None:
        resolution = self.resolution()
        resolution["binding_digest"] = "0" * 64
        with self.assertRaisesRegex(RepositoryError, "PROFILE_TASK_BINDING_DIGEST_MISMATCH"):
            self.adapter.materialize(resolution)

    def test_source_byte_drift_blocks(self) -> None:
        resolution = self.resolution()
        (self.root / "skills/story/agents/x.md").write_text("changed", encoding="utf-8")
        with self.assertRaisesRegex(RepositoryError, "PROFILE_TASK_BINDING_SOURCE_SHA_MISMATCH"):
            self.adapter.materialize(resolution)

    def test_source_escape_blocks(self) -> None:
        resolution = self.resolution()
        outside = self.root / "outside.md"
        outside.write_text("outside", encoding="utf-8")
        resolution["binding"]["source_refs"].append({"path": "outside.md", "sha256": sha(outside.read_bytes())})
        resolution["binding_digest"] = hashlib.sha256(canonical(resolution["binding"]).encode("utf-8")).hexdigest()
        with self.assertRaisesRegex(RepositoryError, "PROFILE_TASK_BINDING_SOURCE_PATH_ESCAPE"):
            self.adapter.materialize(resolution)

    def test_schema_sha_mismatch_blocks(self) -> None:
        resolution = self.resolution()
        resolution["binding"]["runtime_schema"]["sha256"] = "0" * 64
        resolution["binding_digest"] = hashlib.sha256(canonical(resolution["binding"]).encode("utf-8")).hexdigest()
        with self.assertRaisesRegex(RepositoryError, "PROFILE_TASK_BINDING_SCHEMA_SHA_MISMATCH"):
            self.adapter.materialize(resolution)

    def test_validator_sha_mismatch_blocks(self) -> None:
        resolution = self.resolution()
        resolution["binding"]["deterministic_validator"]["sha256"] = "0" * 64
        resolution["binding_digest"] = hashlib.sha256(canonical(resolution["binding"]).encode("utf-8")).hexdigest()
        with self.assertRaisesRegex(RepositoryError, "PROFILE_TASK_BINDING_VALIDATOR_SHA_MISMATCH"):
            self.adapter.materialize(resolution)

    def test_judge_independence_blocks(self) -> None:
        resolution = self.resolution()
        resolution["binding"]["judge_binding"]["worker_must_not_execute_own_judge"] = False
        resolution["binding_digest"] = hashlib.sha256(canonical(resolution["binding"]).encode("utf-8")).hexdigest()
        with self.assertRaisesRegex(RepositoryError, "PROFILE_TASK_BINDING_JUDGE_UNRESOLVED"):
            self.adapter.materialize(resolution)

    def test_context_budget_blocks(self) -> None:
        resolution = self.resolution()
        resolution["binding"]["model_context"]["max_chars"] = 5
        resolution["binding_digest"] = hashlib.sha256(canonical(resolution["binding"]).encode("utf-8")).hexdigest()
        with self.assertRaisesRegex(RepositoryError, "PROFILE_TASK_BINDING_MODEL_CONTEXT_BUDGET_EXCEEDED"):
            self.adapter.materialize(resolution)

    def test_adapter_does_not_require_profiles_root_for_embedded_mode(self) -> None:
        self.assertFalse((self.root / "profiles").exists())
        materialized = self.adapter.materialize(self.resolution())
        self.assertEqual(materialized.source_root, "skills/story")


if __name__ == "__main__":
    unittest.main()
