from __future__ import annotations

import subprocess
import unittest
from pathlib import Path


class DeployAssetTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(__file__).resolve().parents[1]

    def test_shell_scripts_parse_and_install_does_not_install_llama_or_model(self) -> None:
        for name in ("inspect_vps.sh", "install.sh"):
            path = self.root / "scripts" / name
            subprocess.run(["bash", "-n", str(path)], check=True)
        installer = (self.root / "scripts/install.sh").read_text(encoding="utf-8")
        self.assertNotIn("llama.cpp", installer)
        self.assertNotIn("huggingface", installer.lower())
        self.assertNotIn("git clone", installer)
        self.assertNotIn("wget ", installer)
        self.assertIn("SOURCE_SHA_REQUIRED_WITHOUT_GIT", installer)
        self.assertLess(installer.index("inspect_vps.sh"), installer.index("python3 -m venv"))

    def test_systemd_unit_is_loopback_single_worker_and_hardened(self) -> None:
        unit = (self.root / "deploy/lf-profile-runtime-api.service").read_text(encoding="utf-8")
        env = (self.root / "deploy/profile-runtime-api.env.example").read_text(encoding="utf-8")
        self.assertIn("NoNewPrivileges=true", unit)
        self.assertIn("ProtectSystem=strict", unit)
        self.assertIn("MemoryMax=768M", unit)
        self.assertIn("PROFILE_RUNTIME_API_HOST=127.0.0.1", env)
        self.assertIn("PROFILE_RUNTIME_MAX_WORKERS=1", env)
        self.assertIn("PROFILE_RUNTIME_ALLOW_MODEL_IMAGE=false", env)

    def test_worker_timeout_ceiling_is_900_seconds(self) -> None:
        worker = (self.root / "scripts/hetzner_queue_worker.py").read_text(encoding="utf-8")
        env = (self.root / "deploy/profile-runtime-worker.env.example").read_text(encoding="utf-8")
        self.assertIn('PROFILE_RUNTIME_WORKER_JOB_TIMEOUT_SECONDS", "900"', worker)
        self.assertNotIn('PROFILE_RUNTIME_WORKER_JOB_TIMEOUT_SECONDS", "1200"', worker)
        self.assertIn("PROFILE_RUNTIME_WORKER_JOB_TIMEOUT_SECONDS=900", env)

    def test_benchmark_is_pinned_to_fixed_artifact(self) -> None:
        harness = (self.root / "scripts/run_benchmark.py").read_text(encoding="utf-8")
        self.assertIn("ee36e056038832e9efbd0a369ded22808614c0c9a3f8ea7766e22f739ecdb287", harness)
        self.assertIn("ARTIFACT_SIZE = (1600, 1000)", harness)
        self.assertIn('"ready_claimed": False', harness)


if __name__ == "__main__":
    unittest.main()
