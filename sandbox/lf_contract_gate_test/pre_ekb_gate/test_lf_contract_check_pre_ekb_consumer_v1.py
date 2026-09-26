#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import inspect
from pathlib import Path

HERE = Path(__file__).resolve().parent
TARGET = HERE / "lf_contract_check_pre_ekb_consumer_v1.py"

spec = importlib.util.spec_from_file_location("lf_contract_check_pre_ekb_consumer_v1_tested", TARGET)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

module.run_self_test()

source = TARGET.read_text(encoding="utf-8")
assert "public.lf_record_gate_checks_v1" in source
assert "public.lf_pre_ekb_gate_consumer_v1" in source
assert "public.lf_write_pipeline_ekb_v1" not in inspect.getsource(module.build_payloads)
assert "public.lf_write_pipeline_ekb_v1" not in inspect.getsource(module.execute)
assert "PRE_EKB_GATE" in source
assert module.OPERATION_CODE == "GITHUB_CONTRACT_GATE_LF"
assert module.CANONICAL_STEP_ID == "contract_judge"

print("PASS_LF_CONTRACT_PRE_EKB_CONSUMER_REGRESSION checks=7")
