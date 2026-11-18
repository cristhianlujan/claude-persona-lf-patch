"""Fleet conformance across API consumer, native selector and real projection sources.

No profile/model execution, Supabase access or runtime receipt generation occurs.
Native runner execution is intercepted before spawning a subprocess.
"""
from __future__ import annotations
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "services/profile_runtime_api"))
os.environ.setdefault("LF_PROFILE_EDGE_URL", "http://127.0.0.1:1")
from profile_runtime_api.repository import RepositoryBindings

spec = importlib.util.spec_from_file_location("binding_conformance_native", ROOT / "scripts/lf_profile_native_resume.py")
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)

PENDING_OWNER_DECISION = {
    "evidence_lineage_reviewer_lf",
    "frontend_prototype_architect_lf",
    "gamification_system_architect",
    "saly_product_director",
    "ux_product_experience_architect_lf",
}
FORMS = {
    "ui_architect": [
        ({"output_type": "PRODUCTION_UI_SPEC"}, "UI_PRODUCTION_SPEC", "schemas/ui_production_spec.schema.json"),
        ({"decision_subject": "layout edge"}, "UI_FOCUSED_DECISION", "schemas/ui_focused_decision.schema.json"),
        ({"pipeline_action": "RETURN"}, "UI_MISSING_INPUT", "schemas/ui_missing_input.schema.json"),
    ],
    "product_director_lf": [
        ({"output_type": "PRODUCT_DIRECTION_SPEC"}, "AUTO", "schemas/product_direction_spec.schema.json"),
        ({"output_type": "PRODUCT_MISSING_INPUT_STATE"}, "PRODUCT_MISSING_INPUT_STATE", "schemas/product_missing_input.schema.json"),
        ({"output_type": "BLOCKED_PRODUCT_RISK"}, "BLOCKED_PRODUCT_RISK", "schemas/product_blocked_risk.schema.json"),
    ],
}

class ProbeIntercepted(Exception):
    pass

class FleetRuntimeBindingConformance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.repository = RepositoryBindings(ROOT, max_prompt_chars=120_000)
        cls.folders = sorted(p for p in (ROOT / "profiles").iterdir() if p.is_dir() and not p.name.startswith("_"))

    def test_00_missing_bindings_are_explicit_owner_decisions(self):
        missing = {p.name for p in self.folders if not (p / "contracts/runtime_binding.json").is_file()}
        self.assertEqual(missing, PENDING_OWNER_DECISION, "SIN_BINDING_DECLARADO: requieren decision del dueno; no autogenerar")
        print("SIN_BINDING_DECLARADO: " + ", ".join(sorted(missing)) + " | DECISION_DUENO_PENDIENTE")

    def test_01_all_declared_bindings_are_conformant_at_both_consumers(self):
        defects = []
        for folder in self.folders:
            slug = folder.name
            binding_path = folder / "contracts/runtime_binding.json"
            if not binding_path.is_file():
                continue
            raw = json.loads(binding_path.read_text(encoding="utf-8"))
            try:
                binding = self.repository.runtime_binding(slug)
                assert binding is not None
                self.repository.validate_profile_identity(slug, raw["profile_code"])
                validator_module = self.repository.load_validator(slug)
                assert callable(getattr(validator_module, binding.canonical_validator_callable, None))
                utility = self.repository.load_semantic_utility(slug)
                assert utility and callable(getattr(*utility, None))
            except Exception as exc:
                defects.append(f"{slug}: API_BINDING {type(exc).__name__}: {exc}")

            validator = raw.get("canonical_validator")
            if not isinstance(validator, dict) or validator.get("transport") not in {"STDIN_JSON", "JSON_FILE_ARGUMENT"}:
                defects.append(f"{slug}: NATIVE_VALIDATOR_TRANSPORT_REQUIRED")
            context = raw.get("model_context")
            if not isinstance(context, dict) or not isinstance(context.get("allow_additional_sources"), bool):
                defects.append(f"{slug}: MODEL_CONTEXT_ADDITIONAL_SOURCES_REQUIRED")
            else:
                try:
                    sources = self.repository.profile_sources(slug, context["required_source_refs"])
                    projected = self.repository.profile_model_sources(slug, sources)
                    actual_chars = sum(len(item["content"]) for item in projected)
                    max_chars = context["source_projection"]["max_chars"]
                    if actual_chars > max_chars:
                        defects.append(f"{slug}: MODEL_CONTEXT_BUDGET {actual_chars}>{max_chars}")
                except Exception as exc:
                    defects.append(f"{slug}: MODEL_CONTEXT {type(exc).__name__}: {exc}")

            cases = FORMS.get(slug, [({}, "AUTO", raw.get("runtime_schema", {}).get("default"))])
            for payload, mode, expected in cases:
                try:
                    resolved = self.repository.runtime_schema(slug, mode)
                    actual = resolved.source_refs[0].replace(f"profiles/{slug}/", "")
                    if actual != expected:
                        defects.append(f"{slug}: API_SCHEMA {mode}: {actual} != {expected}")
                except Exception as exc:
                    defects.append(f"{slug}: API_SCHEMA {mode}: {type(exc).__name__}: {exc}")
                try:
                    self._native_probe(slug, raw, payload, expected)
                except Exception as exc:
                    defects.append(f"{slug}: NATIVE_SCHEMA {mode}: {type(exc).__name__}: {exc}")
        self.assertFalse(defects, "\n" + "\n".join(defects))

    def test_02_schema_selection_rejects_unknown_and_ambiguous_forms(self):
        for slug, mode in (("ui_architect", "UI_UNDECLARED"), ("product_director_lf", "UNKNOWN")):
            with self.subTest(profile=slug):
                with self.assertRaises(Exception) as raised:
                    self.repository.runtime_schema(slug, mode)
                self.assertIn("RUNTIME_OUTPUT_MODE_UNSUPPORTED", str(raised.exception))
        with self.assertRaises(Exception) as conflict:
            self.repository.runtime_schema(
                "ui_architect", "UI_FOCUSED_DECISION",
                profile_output={"pipeline_action": "RETURN"}
            )
        self.assertIn("RUNTIME_OUTPUT_MODE_UNSUPPORTED", str(conflict.exception))
        with self.assertRaises(Exception) as ambiguous:
            self.repository.runtime_schema(
                "ui_architect", profile_output={
                    "decision_subject": "layout", "pipeline_action": "RETURN"
                }
            )
        self.assertIn("RUNTIME_OUTPUT_MODE_UNSUPPORTED", str(ambiguous.exception))

    def test_03_final_bound_consumer_uses_same_real_schema_and_transport(self):
        """Exercise final source-SHA-bound consumer on synthetic negatives.

        The canonical JSON Schema rejects incomplete payloads before any
        profile-local validator or model is executed; no RUN/DB is touched.
        """
        runner_spec = importlib.util.spec_from_file_location(
            "lf_fleet_bound_runner",
            ROOT / "skills/profile_creator/validators/run_bound_profile_output_validator_v1.py",
        )
        runner = importlib.util.module_from_spec(runner_spec)
        runner_spec.loader.exec_module(runner)

        cases = [
            ("ui_architect", payload, expected)
            for payload, _mode, expected in FORMS["ui_architect"]
        ] + [
            ("product_director_lf", payload, expected)
            for payload, _mode, expected in FORMS["product_director_lf"]
        ]
        for slug, payload, expected in cases:
            with self.subTest(profile=slug, expected=expected), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                binding = json.loads((ROOT / f"profiles/{slug}/contracts/runtime_binding.json").read_text(encoding="utf8"))
                refs = [
                    f"profiles/{slug}/contracts/runtime_binding.json",
                    f"profiles/{slug}/{expected}",
                    f"profiles/{slug}/{binding['canonical_validator']['path']}",
                    "services/profile_runtime_api/profile_runtime_api/runtime_schema_selection.py",
                ]
                for ref in refs:
                    target = root / ref
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes((ROOT / ref).read_bytes())
                raw_ref = "profile-native-test-output.json"
                (root / raw_ref).write_text(json.dumps(payload), encoding="utf8")
                def digest(ref):
                    return hashlib.sha256((root / ref).read_bytes()).hexdigest()
                packet = {
                    "schema": "PROFILE_OUTPUT_VALIDATION_BINDING_V1",
                    "operation_code": "EJECUCION_PERFIL_LF",
                    "profile_slug": slug,
                    "validator_transport": binding["canonical_validator"]["transport"],
                    "expected_valid": False,
                    "runtime_binding_sha256": digest(refs[0]),
                    "schema_ref": refs[1],
                    "schema_sha256": digest(refs[1]),
                    "validator_ref": refs[2],
                    "validator_sha256": digest(refs[2]),
                    "raw_output_ref": raw_ref,
                    "raw_output_sha256": digest(raw_ref),
                }
                result = runner.validate_bound_output(root, packet)
                self.assertEqual(result["status"], "EXPECTED_NEGATIVE_REJECTED_BY_SHAPE", result)
                self.assertTrue(result["source_readback_matched"])
                self.assertTrue(result["structural_check_executed"])
                self.assertFalse(result["profile_validator_executed"])
                wrong_transport = dict(packet, validator_transport=(
                    "STDIN_JSON" if packet["validator_transport"] == "JSON_FILE_ARGUMENT" else "JSON_FILE_ARGUMENT"
                ))
                blocked = runner.validate_bound_output(root, wrong_transport)
                self.assertEqual(blocked["blocking_codes"], ["RUNTIME_BINDING_TRANSPORT_NOT_CANONICAL"])

    def _native_probe(self, slug, raw, payload, expected):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            refs = [f"profiles/{slug}/contracts/runtime_binding.json", f"profiles/{slug}/{raw['canonical_validator']['path']}"]
            refs += [f"profiles/{slug}/{rel}" for rel in set([raw["runtime_schema"]["default"], *raw["runtime_schema"].get("output_modes", {}).values()])]
            for ref in refs:
                dst = root / ref
                dst.parent.mkdir(parents=True, exist_ok=True)
                dst.write_bytes((ROOT / ref).read_bytes())
            with mock.patch.object(native.Path, "cwd", return_value=root), mock.patch.object(native.subprocess, "run", side_effect=ProbeIntercepted):
                with self.assertRaises(ProbeIntercepted):
                    native.run_bound_validator(f"profiles/{slug}/SKILL.md", raw["profile_code"], payload)
            packet = json.loads((root / "profile-native-validation-binding.json").read_text(encoding="utf-8"))
            selected = packet["schema_ref"].replace(f"profiles/{slug}/", "")
            self.assertEqual(selected, expected)
            self.assertEqual(packet["validator_transport"], raw["canonical_validator"]["transport"])

if __name__ == "__main__":
    unittest.main()
