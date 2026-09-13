from __future__ import annotations

import unittest
from pathlib import Path


class NoncanonicalObservationAdmissionMigrationTest(unittest.TestCase):
    def test_migration_fail_closes_runtime_incompatible_observations(self) -> None:
        repo = Path(__file__).resolve().parents[3]
        migration = repo / "supabase/migrations/20260913034250_lf_profile_runtime_noncanonical_observation_admission_v1.sql"
        sql = migration.read_text(encoding="utf-8")
        for token in (
            "HETZNER_NONCANONICAL_OBSERVATION_OBJECT_REQUIRED",
            "HETZNER_NONCANONICAL_OBSERVATION_KEYS_INVALID",
            "HETZNER_NONCANONICAL_OBSERVATION_TEXT_INVALID",
            "HETZNER_NONCANONICAL_OBSERVATION_BBOX_INVALID",
            "HETZNER_NONCANONICAL_OBSERVATION_CONF_INVALID",
            "HETZNER_NONCANONICAL_OBSERVATION_ID_INVALID",
        ):
            self.assertIn(token, sql)
        self.assertIn("jsonb_object_keys(v_obs)", sql)
        self.assertIn("jsonb_array_length(v_obs->'bbox') <> 4", sql)


if __name__ == "__main__":
    unittest.main()
