#!/usr/bin/env python3
from __future__ import annotations

import json
import statistics
import sys
import tempfile
import time as wall_time
from contextlib import contextmanager
from pathlib import Path
from types import SimpleNamespace
from typing import Any, Iterator
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
SERVICE = REPO / "services" / "profile_runtime_api"
for path in (str(REPO), str(SERVICE)):
    if path not in sys.path:
        sys.path.insert(0, path)

from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import InMemoryMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import InMemorySpanExporter, SimpleSpanProcessor

from profile_runtime_api import engine as engine_module
from profile_runtime_api import llama as llama_module
from profile_runtime_api.cache import StructuralCache
from profile_runtime_api.engine import ProfileRuntimeEngine
from profile_runtime_api.hashing import canonical_json_sha256
from profile_runtime_api.llama import governed_generation_schema
from profile_runtime_api.models import ProfileTask, QueueExecuteRequest
from profile_runtime_api.settings import Settings

OTEL_PIN = "1.44.0"
SENSITIVE_INPUT = "SENSITIVE-USER-INPUT-DO-NOT-EXPORT"
SENSITIVE_OUTPUT = "SENSITIVE-MODEL-OUTPUT-DO-NOT-EXPORT"
FIXED_ATTESTED_AT = "2026-09-12T07:15:00Z"
FIXED_TOKEN_HEX = "0123456789abcdef0123456789abcdef"


def valid_quality_output() -> str:
    return json.dumps(
        {
            "review_id": "review-R03B-001",
            "reviewed_artifact": "R03-B deterministic telemetry candidate",
            "verdict": "BLOCK_PIPELINE",
            "score_breakdown": {
                "contract_schema_compliance": 5,
                "evidence_integrity": 4,
                "lf_safety_governance": 5,
                "handoff_readiness": 2,
                "leakage_scope_control": 5,
                "total": 21,
            },
            "evidence_map": [
                {
                    "ref": "visible://r03b",
                    "observation": "Deterministic telemetry fixture is visible to the test runtime.",
                }
            ],
            "blocking_codes": ["INDEPENDENT_SEMANTIC_REVIEW_NOT_EXECUTED"],
            "repair_actions": [],
            "remaining_risks": [SENSITIVE_OUTPUT],
            "next_gate": "STOP",
            "routing": {
                "activation_path": "DIRECT",
                "via": "ORCHESTRATOR",
                "pipeline_action": "BLOCK_PIPELINE",
                "resolution_target": "NONE",
            },
        },
        ensure_ascii=False,
        sort_keys=True,
    )


class FakeLlamaClient:
    def __init__(self, output: str) -> None:
        self.output = output
        self.chat_calls = 0

    def health(self) -> dict[str, Any]:
        return {"ready": True, "status": "READY", "model_ids": ["fake-local-model"]}

    def chat(self, **kwargs: Any) -> dict[str, Any]:
        self.chat_calls += 1
        generation_schema, generation_policy = governed_generation_schema(
            kwargs["schema"],
            profile_slug=kwargs["profile_slug"],
            schema_mode=kwargs.get("schema_mode", "AUTO"),
        )
        return {
            "content": self.output,
            "id": "completion-r03b-fixed",
            "model": "fake-local-model",
            "usage": {"prompt_tokens": 10, "completion_tokens": 10},
            "timings": {"predicted_ms": 1.0},
            "finish_reason": "stop",
            "generation_schema_sha256": canonical_json_sha256(generation_schema),
            "generation_schema_policy": generation_policy,
        }


class DeterministicPerfCounter:
    def __init__(self) -> None:
        self.values = iter((100.0, 100.0, 100.005, 100.010))

    def perf_counter(self) -> float:
        return next(self.values)


class TelemetryHarness:
    def __init__(self) -> None:
        resource = Resource.create(
            {
                "service.name": "lf-profile-runtime-r03b-spike",
                "service.version": "r03b",
                "deployment.environment": "isolated-spike",
            }
        )
        self.span_exporter = InMemorySpanExporter()
        self.tracer_provider = TracerProvider(resource=resource)
        self.tracer_provider.add_span_processor(SimpleSpanProcessor(self.span_exporter))
        self.tracer = self.tracer_provider.get_tracer("lf.platform-adopt.r03b")

        self.metric_reader = InMemoryMetricReader()
        self.meter_provider = MeterProvider(resource=resource, metric_readers=[self.metric_reader])
        self.meter = self.meter_provider.get_meter("lf.platform-adopt.r03b")
        self.calls = self.meter.create_counter("lf.profile.runtime.calls")
        self.blocked = self.meter.create_counter("lf.profile.runtime.blocked")
        self.duration = self.meter.create_histogram("lf.profile.runtime.duration", unit="ms")

    def execute(self, engine: ProfileRuntimeEngine, request: QueueExecuteRequest) -> dict[str, Any]:
        request_hash = canonical_json_sha256(request.model_dump(mode="json"))
        started = wall_time.perf_counter_ns()
        with self.tracer.start_as_current_span("lf.profile.queue_execute") as span:
            span.set_attribute("lf.profile_code", request.profile.profile_code)
            span.set_attribute("lf.gate", "PROFILE_RUNTIME_QUEUE_EXECUTION")
            span.set_attribute("lf.request_sha256", request_hash)
            result = engine.run_queue_execute(request)
            status = result["result"]["runtime_completion"]["status"]
            blocking_codes = result["result"]["runtime_completion"].get("blocking_codes", [])
            result_hash = canonical_json_sha256(result)
            span.set_attribute("lf.status", status)
            span.set_attribute("lf.result_sha256", result_hash)
            span.set_attribute("lf.block_code", blocking_codes[0] if blocking_codes else "")
            receipt = result["result"]["runtime_completion"].get("receipt")
            if isinstance(receipt, dict) and receipt.get("receipt_sha256"):
                span.set_attribute("lf.receipt_sha256", str(receipt["receipt_sha256"]))
            elapsed_ms = (wall_time.perf_counter_ns() - started) / 1_000_000
            metric_attrs = {"lf.profile_code": request.profile.profile_code, "lf.status": status}
            self.calls.add(1, metric_attrs)
            if status != "PASS":
                self.blocked.add(1, metric_attrs)
            self.duration.record(elapsed_ms, metric_attrs)
        return result

    def serialized_telemetry(self) -> str:
        spans = []
        for span in self.span_exporter.get_finished_spans():
            spans.append(
                {
                    "name": span.name,
                    "attributes": dict(span.attributes or {}),
                    "events": [
                        {"name": event.name, "attributes": dict(event.attributes or {})}
                        for event in span.events
                    ],
                }
            )
        metrics = self.metric_reader.get_metrics_data()
        metric_names: list[str] = []
        if metrics is not None:
            for resource_metrics in metrics.resource_metrics:
                for scope_metrics in resource_metrics.scope_metrics:
                    for metric in scope_metrics.metrics:
                        metric_names.append(metric.name)
        return json.dumps(
            {"spans": spans, "metric_names": sorted(metric_names)},
            ensure_ascii=False,
            sort_keys=True,
        )


@contextmanager
def deterministic_runtime_clock() -> Iterator[None]:
    fake_time = DeterministicPerfCounter()
    fake_secrets = SimpleNamespace(token_hex=lambda _n: FIXED_TOKEN_HEX)
    with (
        patch.object(engine_module, "time", fake_time),
        patch.object(llama_module, "secrets", fake_secrets),
        patch.object(llama_module, "utc_now", lambda: FIXED_ATTESTED_AT),
    ):
        yield


@contextmanager
def deterministic_attestation_only() -> Iterator[None]:
    fake_secrets = SimpleNamespace(token_hex=lambda _n: FIXED_TOKEN_HEX)
    with (
        patch.object(llama_module, "secrets", fake_secrets),
        patch.object(llama_module, "utc_now", lambda: FIXED_ATTESTED_AT),
    ):
        yield


def make_engine(state_dir: Path) -> ProfileRuntimeEngine:
    settings = Settings(
        repo_root=REPO,
        state_dir=state_dir,
        api_token="r03b-test-token",
        source_sha="794a86fc8ea7fe3921a17bb31b9087c097a01cef",
    )
    engine = ProfileRuntimeEngine(
        settings,
        llama_client=FakeLlamaClient(valid_quality_output()),  # type: ignore[arg-type]
        cache=StructuralCache(state_dir / "cache"),
    )
    engine.initialize()
    return engine


def make_request(*, blocked: bool = False) -> QueueExecuteRequest:
    task = ProfileTask(
        request_id="r03b-queue-blocked" if blocked else "r03b-queue-pass",
        profile_code="PERFIL-QUALITY-PACK",
        profile_slug="quality_pack",
        profile_source_paths=["profiles/quality_pack/SKILL.md"],
        input_literal=(
            SENSITIVE_INPUT
            + " Evaluate the governed candidate without exporting raw input through telemetry."
        ),
        send_image_to_model=blocked,
    )
    return QueueExecuteRequest(profile=task)


def deterministic_parity_case(*, blocked: bool) -> dict[str, Any]:
    request = make_request(blocked=blocked)
    with tempfile.TemporaryDirectory() as direct_tmp, tempfile.TemporaryDirectory() as otel_tmp:
        direct_engine = make_engine(Path(direct_tmp))
        otel_engine = make_engine(Path(otel_tmp))
        with deterministic_runtime_clock():
            direct = direct_engine.run_queue_execute(request)
        telemetry = TelemetryHarness()
        with deterministic_runtime_clock():
            observed = telemetry.execute(otel_engine, request)
        direct_hash = canonical_json_sha256(direct)
        observed_hash = canonical_json_sha256(observed)
        if direct != observed or direct_hash != observed_hash:
            raise AssertionError(f"R03B_RESULT_PARITY_FAILED blocked={blocked}")
        serialized = telemetry.serialized_telemetry()
        for forbidden in (SENSITIVE_INPUT, SENSITIVE_OUTPUT, request.profile.input_literal):
            if forbidden in serialized:
                raise AssertionError("R03B_SENSITIVE_CONTENT_EXPORTED")
        if "input.value" in serialized or "output.value" in serialized:
            raise AssertionError("R03B_CONTENT_ATTRIBUTE_EXPORTED")
        spans = json.loads(serialized)["spans"]
        if len(spans) != 1:
            raise AssertionError("R03B_UNEXPECTED_SPAN_COUNT")
        attrs = spans[0]["attributes"]
        required_attrs = {
            "lf.profile_code",
            "lf.gate",
            "lf.request_sha256",
            "lf.status",
            "lf.result_sha256",
            "lf.block_code",
        }
        if not required_attrs.issubset(attrs):
            raise AssertionError("R03B_REQUIRED_TELEMETRY_ATTRIBUTES_MISSING")
        metric_names = set(json.loads(serialized)["metric_names"])
        if not {"lf.profile.runtime.calls", "lf.profile.runtime.duration"}.issubset(metric_names):
            raise AssertionError("R03B_REQUIRED_METRICS_MISSING")
        return {
            "case": "FAIL_CLOSED" if blocked else "PASS_PATH",
            "direct_sha256": direct_hash,
            "otel_sha256": observed_hash,
            "exact_result_parity": True,
            "status": observed["result"]["runtime_completion"]["status"],
            "blocking_codes": observed["result"]["runtime_completion"].get("blocking_codes", []),
            "span_count": len(spans),
            "metric_names": sorted(metric_names),
            "raw_sensitive_content_exported": False,
        }


def benchmark(samples: int = 100, warmups: int = 10) -> dict[str, Any]:
    request = make_request(blocked=False)
    with tempfile.TemporaryDirectory() as tmp:
        engine = make_engine(Path(tmp))
        telemetry = TelemetryHarness()

        def direct_once() -> None:
            with deterministic_attestation_only():
                engine.run_queue_execute(request)

        def otel_once() -> None:
            with deterministic_attestation_only():
                telemetry.execute(engine, request)

        for _ in range(warmups):
            direct_once()
            otel_once()

        direct_ms: list[float] = []
        otel_ms: list[float] = []
        for _ in range(samples):
            start = wall_time.perf_counter_ns()
            direct_once()
            direct_ms.append((wall_time.perf_counter_ns() - start) / 1_000_000)
            start = wall_time.perf_counter_ns()
            otel_once()
            otel_ms.append((wall_time.perf_counter_ns() - start) / 1_000_000)

    def p95(values: list[float]) -> float:
        ordered = sorted(values)
        return ordered[max(0, int(len(ordered) * 0.95) - 1)]

    direct_median = statistics.median(direct_ms)
    otel_median = statistics.median(otel_ms)
    return {
        "scope": "LOCAL_FAKE_MODEL_QUEUE_EXECUTION_IN_MEMORY_OTEL_EXPORT",
        "samples": samples,
        "warmups": warmups,
        "direct_median_ms": round(direct_median, 6),
        "direct_p95_ms": round(p95(direct_ms), 6),
        "otel_median_ms": round(otel_median, 6),
        "otel_p95_ms": round(p95(otel_ms), 6),
        "absolute_median_overhead_ms": round(otel_median - direct_median, 6),
    }


def main() -> int:
    pass_case = deterministic_parity_case(blocked=False)
    fail_case = deterministic_parity_case(blocked=True)
    if fail_case["blocking_codes"] != ["QUEUE_NATIVE_IMAGE_REQUIRES_GOVERNED_ENVELOPE"]:
        raise AssertionError("R03B_FAIL_CLOSED_CODE_DRIFT")
    perf = benchmark()
    report = {
        "schema": "LF_PLATFORM_ADOPT_R03B_OTEL_SPIKE_REPORT_V1",
        "gate": "ADOPT-R03-B",
        "opentelemetry_pin": OTEL_PIN,
        "base_main": "794a86fc8ea7fe3921a17bb31b9087c097a01cef",
        "export_mode": "IN_MEMORY_ONLY",
        "external_export": False,
        "model_network_call": False,
        "production_effect": False,
        "content_capture": "OFF",
        "cases": [pass_case, fail_case],
        "benchmark": perf,
        "checks": {
            "exact_pass_result_hash_parity": pass_case["exact_result_parity"],
            "exact_fail_closed_result_hash_parity": fail_case["exact_result_parity"],
            "fail_closed_code_preserved": True,
            "raw_sensitive_content_exported": False,
            "traces_captured": True,
            "metrics_captured": True,
            "external_export": False,
        },
        "status": "PASS",
        "claim_ceiling": "ISOLATED_OTEL_PARITY_PRIVACY_AND_SYNTHETIC_OVERHEAD_ONLY_NOT_PRODUCTION_INSTRUMENTATION",
    }
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
