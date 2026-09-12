#!/usr/bin/env python3
import tempfile
from pathlib import Path

from guard_no_model_weight_acquisition import scan_workflows


def write(root: Path, name: str, content: str):
    path = root / name
    path.write_text(content, encoding="utf-8")
    return path


def main():
    passed = 0
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)

        write(root, "safe.yml", """
name: Profile Driven Screen Generation Gate
on: [pull_request]
jobs:
  contract:
    steps:
      - run: python3 sandbox/lf_contract_gate_test/profile_execution_runtime/run_native_execution_contract_tests.py
""")
        assert scan_workflows(root) == []
        passed += 1

        write(root, "unsafe-hf.yml", """
name: S26 runtime
jobs:
  runtime:
    steps:
      - run: curl https://huggingface.co/org/model/resolve/main/model.gguf -o model.gguf
""")
        findings = scan_workflows(root)
        assert any("HUGGINGFACE_DOWNLOAD" in x for x in findings)
        assert any("GGUF_WEIGHT" in x for x in findings)
        passed += 1

        (root / "unsafe-hf.yml").unlink()
        write(root, "unsafe-safe.yml", """
name: lf-profile-runtime
jobs:
  runtime:
    steps:
      - run: python -c "from huggingface_hub import snapshot_download; snapshot_download('x')"
""")
        findings = scan_workflows(root)
        assert any("HF_SNAPSHOT_DOWNLOAD" in x for x in findings)
        passed += 1

        write(root, "unrelated.yml", """
name: unrelated
jobs:
  docs:
    steps:
      - run: echo model.gguf
""")
        (root / "unsafe-safe.yml").unlink()
        assert scan_workflows(root) == []
        passed += 1

    print(f"S26_MODEL_WEIGHT_GUARD_TESTS_PASS {passed}/4")


if __name__ == "__main__":
    main()
