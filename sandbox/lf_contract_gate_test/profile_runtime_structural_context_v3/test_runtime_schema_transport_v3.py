#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import os
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace

REPO = Path(__file__).resolve().parents[3]
RUNTIME_DIR = REPO / "sandbox/lf_contract_gate_test/profile_execution_runtime"
MODULE_PATH = RUNTIME_DIR / "github_actions_local_runtime.py"
if str(RUNTIME_DIR) not in sys.path:
    sys.path.insert(0, str(RUNTIME_DIR))


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    runtime = load(MODULE_PATH, "runtime_schema_transport_v3")

    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        schema = work / "profiles/product_director_lf/schemas/runtime_output.schema.json"
        schema.parent.mkdir(parents=True)
        schema.write_text('{"type":"object","required":["worker"]}\n', encoding="utf-8")

        cli = work / "llama-cli"
        model = work / "model.gguf"
        mmproj = work / "mmproj.gguf"
        cli.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        cli.chmod(0o755)
        model.write_bytes(b"model")
        mmproj.write_bytes(b"mmproj")

        assets = {
            "LF_LLAMA_CLI_PATH": cli,
            "LF_MODEL_PATH": model,
            "LF_MMPROJ_PATH": mmproj,
        }
        runtime._required_asset = lambda env_name, expected_sha=None: assets[env_name]
        runtime._require_zero_cost_runner = lambda: {
            "repository": runtime.TARGET_REPOSITORY,
            "runner_label": "ubuntu-latest",
            "visibility": "public",
        }

        observed: dict[str, object] = {}

        def fake_run(command, **kwargs):
            observed["command"] = list(command)
            assert "-jf" in command, "structured schema was materialized but not transported to llama.cpp"
            schema_arg = Path(command[command.index("-jf") + 1])
            assert schema_arg.resolve() == schema.resolve(), (schema_arg, schema)
            output_arg = Path(command[command.index("-o") + 1])
            output_arg.write_text('{"worker":"Product Director LF"}\n', encoding="utf-8")
            return SimpleNamespace(returncode=0, stdout="", stderr="")

        runtime.subprocess.run = fake_run
        old_env = {key: os.environ.get(key) for key in ("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "GITHUB_SHA")}
        os.environ["GITHUB_RUN_ID"] = "12345"
        os.environ["GITHUB_RUN_ATTEMPT"] = "1"
        os.environ["GITHUB_SHA"] = "a" * 40
        try:
            adapter = runtime.GitHubHostedLlamaCppAdapter(work_dir=work)
            response = adapter.execute({
                "profile_slug": "product_director_lf",
                "profile_code": "PRODUCT_DIRECTOR_LF",
                "operation_code": "EJECUCION_PERFIL_LF",
                "profile_sources": [{"ref": "profiles/product_director_lf/profile.md", "content": "Return governed output."}],
                "input_literal": "Review B2B-CARGA-001",
                "request_sha256": "b" * 64,
                "profile_source_sha256": "c" * 64,
                "input_sha256": "d" * 64,
            })
        finally:
            for key, value in old_env.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value

        command = observed.get("command")
        assert isinstance(command, list) and "-jf" in command
        attestation = response["runtime_attestation"]
        assert attestation["structured_output_schema_ref"] == "profiles/product_director_lf/schemas/runtime_output.schema.json"
        assert attestation["structured_output_schema_sha256"] == sha256_file(schema)
        assert response["raw_output"] == '{"worker":"Product Director LF"}'

    print("RUNTIME_SCHEMA_TRANSPORT_V3_PASS materialized=true llama_jf_bound=true attested=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
