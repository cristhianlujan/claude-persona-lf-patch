from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

from profile_runtime_api.cache import CacheError, StructuralCache, make_cache_key


class CacheTest(unittest.TestCase):
    def test_key_matches_repository_v3_contract(self) -> None:
        root = Path(__file__).resolve().parents[3]
        source = (
            root
            / "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/cache_key_v3.py"
        )
        spec = importlib.util.spec_from_file_location("repository_cache_key_v3", source)
        self.assertIsNotNone(spec)
        self.assertIsNotNone(spec.loader if spec else None)
        module = importlib.util.module_from_spec(spec)  # type: ignore[arg-type]
        spec.loader.exec_module(module)  # type: ignore[union-attr]
        args = {
            "image_sha": "a" * 64,
            "context_sha": "b" * 64,
            "runtime_version": "runtime/v1",
            "resolver_version": "resolver/v3",
        }
        self.assertEqual(make_cache_key(**args), module.make_cache_key(**args))

    def test_cache_rejects_nested_quality_or_authorization(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            cache = StructuralCache(Path(directory))
            key = make_cache_key(
                image_sha="a" * 64,
                context_sha="b" * 64,
                runtime_version="runtime/v1",
                resolver_version="resolver/v3",
            )
            with self.assertRaisesRegex(CacheError, "semantic_utility"):
                cache.put(key, {"nested": {"semantic_utility": "PASS"}})
            with self.assertRaisesRegex(CacheError, "downstream_authorized"):
                cache.put(key, {"nested": [{"downstream_authorized": True}]})

    def test_disk_round_trip_is_integrity_checked_and_copied(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            cache = StructuralCache(Path(directory))
            key = make_cache_key(
                image_sha="c" * 64,
                context_sha="d" * 64,
                runtime_version="runtime/v1",
                resolver_version="resolver/v3",
            )
            cache.put(key, {"evidence": [{"role": "PAGE_HEADER", "text": "Cargas"}]})
            first = cache.get(key)
            self.assertIsNotNone(first)
            first["evidence"][0]["text"] = "mutated"  # type: ignore[index]
            self.assertEqual(cache.get(key)["evidence"][0]["text"], "Cargas")  # type: ignore[index]


if __name__ == "__main__":
    unittest.main()
