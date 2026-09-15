#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
SERVICE = REPO / "services" / "profile_runtime_api"
for path in (str(HERE), str(REPO), str(SERVICE)):
    if path not in sys.path:
        sys.path.insert(0, path)

from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.trace import format_span_id
from phoenix.client import Client

from profile_runtime_api.hashing import canonical_json_sha256
from run_r03b_otel_spike import (
    SENSITIVE_INPUT,
    SENSITIVE_OUTPUT,
    deterministic_runtime_clock,
    make_engine,
    make_request,
)

PHOENIX_SERVER_PIN = "20.9.0"
PHOENIX_CLIENT_PIN = "3.5.0"
OTEL_PIN = "1.44.0"
PHOENIX_BASE_URL = "http://127.0.0.1:6006"
PHOENIX_OTLP_HTTP = f"{PHOENIX_BASE_URL}/v1/traces"
PROJECT_NAME = "lf-r03c-local-fit"
SPAN_NAME = "lf.r03c.profile_runtime"
LF_EVAL_ANNOTATION = "lf_quality_receipt_copy"


def wait_for_retrieval(client: Client, *, timeout_s: float = 15.0):
    deadline = time.monotonic() + timeout_s
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        try:
            df = client.spans.get_spans_dataframe(project_identifier=PROJECT_NAME)
            if df is not None and not df.empty:
                rendered = df.to_string()
                if SPAN_NAME in rendered:
                    return df
        except Exception as exc:  # bounded local service readiness only
            last_error = exc
        time.sleep(0.25)
    if last_error is not None:
        raise AssertionError(f"R03C_SPAN_RETRIEVAL_TIMEOUT: {last_error}") from last_error
    raise AssertionError("R03C_SPAN_RETRIEVAL_TIMEOUT")


def wait_for_annotation(client: Client, span_id: str, *, timeout_s: float = 10.0):
    deadline = time.monotonic() + timeout_s
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        try:
            df = client.spans.get_span_annotations_dataframe(
                span_ids=[span_id],
                project_identifier=PROJECT_NAME,
            )
            if df is not None and not df.empty:
                rendered = df.to_string()
                if LF_EVAL_ANNOTATION in rendered:
                    return df
        except Exception as exc:
            last_error = exc
        time.sleep(0.25)
    if last_error is not None:
        raise AssertionError(f"R03C_ANNOTATION_RETRIEVAL_TIMEOUT: {last_error}") from last_error
    raise AssertionError("R03C_ANNOTATION_RETRIEVAL_TIMEOUT")


def main() -> int:
    request = make_request(blocked=False)

    with (
        tempfile.TemporaryDirectory() as direct_tmp,
        tempfile.TemporaryDirectory() as phoenix_tmp,
        tempfile.TemporaryDirectory() as post_annotation_tmp,
    ):
        direct_engine = make_engine(Path(direct_tmp))
        phoenix_engine = make_engine(Path(phoenix_tmp))
        post_annotation_engine = make_engine(Path(post_annotation_tmp))

        # Freeze LF-internal runtime timing/attestation fields so exact result/hash
        # comparisons measure Phoenix/OTel influence rather than wall-clock drift.
        with deterministic_runtime_clock():
            direct_result = direct_engine.run_queue_execute(request)
        direct_hash = canonical_json_sha256(direct_result)

        resource = Resource.create(
            {
                "service.name": "lf-profile-runtime-r03c",
                "service.version": "r03c",
                "deployment.environment": "isolated-local-fit",
                "openinference.project.name": PROJECT_NAME,
            }
        )
        provider = TracerProvider(resource=resource)
        exporter = OTLPSpanExporter(
            endpoint=PHOENIX_OTLP_HTTP,
            headers={"x-project-name": PROJECT_NAME},
        )
        provider.add_span_processor(SimpleSpanProcessor(exporter))
        tracer = provider.get_tracer("lf.platform-adopt.r03c")

        request_hash = canonical_json_sha256(request.model_dump(mode="json"))
        export_started = time.perf_counter_ns()
        with tracer.start_as_current_span(SPAN_NAME) as span:
            span_id = format_span_id(span.get_span_context().span_id)
            span.set_attribute("lf.profile_code", request.profile.profile_code)
            span.set_attribute("lf.gate", "PROFILE_RUNTIME_QUEUE_EXECUTION")
            span.set_attribute("lf.request_sha256", request_hash)
            with deterministic_runtime_clock():
                phoenix_result = phoenix_engine.run_queue_execute(request)
            phoenix_hash = canonical_json_sha256(phoenix_result)
            completion = phoenix_result["result"]["runtime_completion"]
            span.set_attribute("lf.status", completion["status"])
            span.set_attribute("lf.result_sha256", phoenix_hash)
            blocking_codes = completion.get("blocking_codes", [])
            span.set_attribute("lf.block_code", blocking_codes[0] if blocking_codes else "")
            receipt = completion.get("receipt")
            if isinstance(receipt, dict) and receipt.get("receipt_sha256"):
                span.set_attribute("lf.receipt_sha256", str(receipt["receipt_sha256"]))

        provider.force_flush(timeout_millis=10_000)
        export_roundtrip_ms = (time.perf_counter_ns() - export_started) / 1_000_000

        if direct_result != phoenix_result or direct_hash != phoenix_hash:
            raise AssertionError("R03C_LF_RESULT_PARITY_FAILED")

        client = Client(base_url=PHOENIX_BASE_URL)
        retrieval_started = time.perf_counter_ns()
        spans_df = wait_for_retrieval(client)
        retrieval_roundtrip_ms = (time.perf_counter_ns() - retrieval_started) / 1_000_000
        spans_rendered = spans_df.to_string()

        for forbidden in (SENSITIVE_INPUT, SENSITIVE_OUTPUT, request.profile.input_literal):
            if forbidden in spans_rendered:
                raise AssertionError("R03C_SENSITIVE_CONTENT_RETRIEVED_FROM_PHOENIX")
        if "attributes.input.value" in spans_rendered or "attributes.output.value" in spans_rendered:
            raise AssertionError("R03C_CONTENT_ATTRIBUTES_PRESENT")
        if direct_hash not in spans_rendered:
            raise AssertionError("R03C_LF_RESULT_HASH_NOT_RETRIEVED")
        if request.profile.profile_code not in spans_rendered:
            raise AssertionError("R03C_PROFILE_CODE_NOT_RETRIEVED")

        annotation_started = time.perf_counter_ns()
        client.spans.add_span_annotation(
            span_id=span_id,
            annotation_name=LF_EVAL_ANNOTATION,
            annotator_kind="CODE",
            label="PASS",
            score=1.0,
            explanation="Observational copy of LF evaluator result; not LF authority or certification.",
            identifier="lf-r03c-v1",
            sync=True,
        )
        annotation_df = wait_for_annotation(client, span_id)
        annotation_roundtrip_ms = (time.perf_counter_ns() - annotation_started) / 1_000_000
        annotations_rendered = annotation_df.to_string()
        if "PASS" not in annotations_rendered or LF_EVAL_ANNOTATION not in annotations_rendered:
            raise AssertionError("R03C_ANNOTATION_VALUE_NOT_RETRIEVED")
        for forbidden in (SENSITIVE_INPUT, SENSITIVE_OUTPUT, request.profile.input_literal):
            if forbidden in annotations_rendered:
                raise AssertionError("R03C_SENSITIVE_CONTENT_IN_ANNOTATION")

        # Prove Phoenix writes are observational: execute LF again in a fresh LF state
        # after the Phoenix annotation write and require exact equality to the baseline.
        with deterministic_runtime_clock():
            post_annotation_result = post_annotation_engine.run_queue_execute(request)
        post_annotation_hash = canonical_json_sha256(post_annotation_result)
        if post_annotation_result != direct_result or post_annotation_hash != direct_hash:
            raise AssertionError("R03C_PHOENIX_ANNOTATION_MUTATED_LF_RESULT")

        provider.shutdown()

        report: dict[str, Any] = {
            "schema": "LF_PLATFORM_ADOPT_R03C_PHOENIX_LOCAL_FIT_REPORT_V1",
            "gate": "ADOPT-R03-C",
            "phoenix_server_pin": PHOENIX_SERVER_PIN,
            "phoenix_client_pin": PHOENIX_CLIENT_PIN,
            "opentelemetry_pin": OTEL_PIN,
            "phoenix_server_license": "Elastic-2.0",
            "phoenix_client_license": "Apache-2.0",
            "technical_fit": "PASS",
            "commercial_license_approval": "REQUIRED_SEPARATELY",
            "project_name": PROJECT_NAME,
            "server_scope": "LOCAL_EPHEMERAL_SELF_HOSTED",
            "external_saas_export": False,
            "phoenix_product_telemetry_enabled": False,
            "model_network_call": False,
            "production_effect": False,
            "lf_direct_sha256": direct_hash,
            "lf_phoenix_wrapped_sha256": phoenix_hash,
            "lf_post_annotation_sha256": post_annotation_hash,
            "exact_lf_result_parity": True,
            "annotation_is_observational_copy_only": True,
            "span_id": span_id,
            "retrieved_span_count": int(len(spans_df)),
            "retrieved_annotation_count": int(len(annotation_df)),
            "raw_sensitive_content_retrieved": False,
            "raw_input_output_attributes_present": False,
            "timings_ms": {
                "lf_execution_plus_local_export_roundtrip": round(export_roundtrip_ms, 6),
                "phoenix_span_retrieval_roundtrip": round(retrieval_roundtrip_ms, 6),
                "phoenix_annotation_write_read_roundtrip": round(annotation_roundtrip_ms, 6),
            },
            "checks": {
                "trace_ingested": True,
                "trace_retrieved": True,
                "safe_lf_metadata_retrieved": True,
                "raw_sensitive_content_absent": True,
                "lf_evaluator_copy_annotation_written": True,
                "lf_evaluator_copy_annotation_retrieved": True,
                "phoenix_annotation_did_not_mutate_lf_result": True,
                "external_saas_export": False,
            },
            "status": "PASS_WITH_LICENSE_GATE",
            "claim_ceiling": "PHOENIX_LOCAL_TECHNICAL_FIT_PASS_OBSERVATIONAL_ONLY_LICENSE_AND_PRODUCTION_APPROVAL_NOT_GRANTED",
        }
        print(json.dumps(report, ensure_ascii=False, sort_keys=True), flush=True)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
