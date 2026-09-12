# R03 — OpenTelemetry + Phoenix Fit-Gap

Strategy: `LF_PLATFORM_ADOPT_FIRST_20260912`  
Base main: `794a86fc8ea7fe3921a17bb31b9087c097a01cef`  
Mode: `READ_ONLY_ARCHITECTURE_FIT_GAP`  
Runtime/production mutation: **none**

## Decision

- **ADOPT** OpenTelemetry as the technical telemetry standard for LF traces and metrics.
- **WRAP / OPTIONAL BACKEND** Phoenix for AI/LLM trace exploration, datasets, evaluations and experiments.
- **KEEP LF** as the sole owner of semantic authority, PASS/FAIL certification, evidence graphs, receipts, hashes, replay certification and migration gates.
- **DEFER** OpenTelemetry Python logs as a required R03 capability because Python logs remain less mature than traces/metrics.
- **DO NOT** export raw prompts, user text, authority documents, card contents, typed context, credentials or full model outputs by default.

## Current LF baseline

### Existing technical metrics

LF already has explicit runtime metrics such as:
- `queue_latency_ms`
- `runtime_prepare_ms`
- `model_download_ms`
- `inference_ms`
- `total_ms`
- runtime/model cache-hit flags
- batch size / parallelism
- per-profile and batch timing

These values are useful but currently live in LF-specific result structures instead of a standard telemetry substrate.

### Existing runtime/job state

`profile_runtime_api` already tracks job lifecycle (`QUEUED`, `RUNNING`, `COMPLETED`, `FAILED`), request hash, timestamps, result/error, recovery after restart and idempotency behavior. This state is operational state and must not be confused with observability spans.

### Existing evidence/certification state

LF persistence V2 is a materially different concern from telemetry. It enforces append-only evidence, provenance, source/config hashes, required artifact families, validation PASS, blocking-record rules and exact reconstruction. This remains canonical LF evidence and is explicitly **not replaced** by OpenTelemetry or Phoenix.

## Capability fit-gap

| Capability | Current LF | OpenTelemetry | Phoenix | Decision |
|---|---|---|---|---|
| Request/service tracing | custom/scattered | strong standard | consumes/displays | ADOPT OTel |
| Runtime timing metrics | custom structures | strong standard | can visualize traces | ADOPT OTel, preserve LF fields during migration |
| Cross-service context propagation | limited/custom | native concern | consumes trace context | ADOPT OTel |
| HTTP/FastAPI instrumentation | no canonical standard layer | mature instrumentation ecosystem | backend only | ADOPT OTel |
| Model/token latency telemetry | explicit in selected LF receipts | GenAI/OpenInference compatible | strong AI UI | WRAP |
| LLM/agent trajectory visualization | custom evidence/replay | spans provide substrate | strong fit | Phoenix optional |
| Offline eval execution | LF judges/scripts | not an eval runner | strong fit | WRAP Phoenix around LF evaluators |
| Experiment comparison | bespoke artifacts | not primary scope | strong fit | Phoenix candidate |
| Semantic Authority | LF-native | out of scope | out of scope | KEEP LF |
| PASS/FAIL certification | LF-native | out of scope | eval result only | KEEP LF |
| Evidence graph / receipts / hashes | LF-native | telemetry is not certification | telemetry/evals are not canonical evidence | KEEP LF |
| Durable execution/checkpoints | LF/LangGraph track | not execution engine | not execution engine | out of R03 |
| Logs | Python/application logging | Python OTel logs less mature than traces/metrics | backend-dependent | DEFER required adoption |

## Required architecture boundary

```text
LF CONTROL / CERTIFICATION PLANE
Cards · EKB · Authority · Typed Context · Contracts
Evidence · Receipts · Hashes · PASS invariants · Replay certification
                         |
                         | correlation ids / governed telemetry projection
                         v
TECHNICAL TELEMETRY PORT
OpenTelemetry traces + metrics
                         |
              +----------+----------+
              |                     |
              v                     v
         OTLP backend          Phoenix / OpenInference
         (replaceable)         (AI observability/evals)
```

### Non-negotiable separation

`OTel span != LF evidence unit`  
`Phoenix eval != LF PASS receipt`  
`Phoenix trace replay != LF certified replay`  
`trace_id != execution authority`

Telemetry may point to LF evidence by opaque identifiers/hashes, but it must not become the evidence itself.

## Proposed LF telemetry projection

### Resource-level attributes

Low-cardinality only:
- `service.name`
- `service.version`
- `deployment.environment`
- `lf.runtime.family`
- `lf.runtime.version`

### Execution span attributes

Allowed by default:
- `lf.execution_id` or opaque execution correlation id
- `lf.profile_code`
- `lf.gate`
- `lf.status`
- `lf.block_code`
- `lf.model_provider`
- `lf.model_id`
- `lf.model_calls`
- `lf.retry_count`
- `lf.cache_hit_runtime`
- `lf.cache_hit_model`
- `lf.input_sha256`
- `lf.output_sha256`
- `lf.receipt_sha256`
- token counts / context proxy when available

### Never-export-by-default fields

- raw user prompt/input
- DNI, phone, email, financial data or other personal data
- raw Typed Context
- Authority source contents
- Cards/EKB bodies
- secrets/API tokens
- raw model completion
- entire LF receipts/evidence payloads
- file contents or image bytes

If content-level tracing is ever required, it must be an explicit opt-in diagnostic mode with redaction, bounded retention and separate authorization.

## Mapping current LF metrics to OTel

| LF field | OTel target |
|---|---|
| `queue_latency_ms` | span duration/event + histogram candidate |
| `runtime_prepare_ms` | child span `runtime.prepare` |
| `model_download_ms` | child span `model.prepare/download` |
| `inference_ms` | child span `model.inference` |
| `total_ms` | parent execution span duration |
| cache hit flags | span attributes + counters |
| model calls | counter / span count |
| retries | counter + retry events |
| batch size | span attribute / histogram candidate |
| parallelism | span attribute |

During migration, LF receipt fields remain unchanged until equivalence is proven. OTel is additive first.

## Phoenix role

Phoenix is a good fit for:
- visual inspection of LLM/agent traces;
- token/latency/cost analysis where available;
- grouping by session/project;
- datasets and experiment comparison;
- attaching evaluation results to traces;
- running or displaying LF evaluator outputs through an adapter.

Phoenix is **not** allowed to:
- decide LF semantic authority;
- replace LF judge contracts;
- certify Golden/production;
- own evidence lineage;
- mutate canonical LF state based on an eval score.

## OpenInference vs OTel GenAI conventions

Use core OpenTelemetry primitives as the stable portability layer. For AI-specific spans, OpenInference is a candidate adapter because Phoenix supports it directly and it remains OTel-compatible. GenAI semantic conventions are evolving, so LF must isolate them behind `LF_TELEMETRY_PORT` rather than spreading vendor/convention-specific keys through core runtime code.

## Risks

1. **Sensitive content leakage** — AI tracing libraries can capture inputs/outputs. Mitigation: metadata/hash-only default, explicit redaction policy, content capture off.
2. **Cardinality explosion** — execution IDs, hashes and error details can create expensive dimensions if promoted to metrics. Mitigation: high-cardinality values stay on spans, not metric labels.
3. **Dual truth** — Phoenix dashboards could be mistaken for LF certification. Mitigation: UI/report labels and contract rule: telemetry is observational only.
4. **Semantic convention churn** — GenAI conventions evolve. Mitigation: adapter boundary and pinned dependencies during spikes.
5. **Instrumentation side effects** — telemetry must not alter retry, exception or fail-closed semantics. Mitigation: deterministic parity tests with telemetry enabled/disabled.

## R03-B result — isolated OpenTelemetry parity/privacy

Status: **PASS**. Evidence run: `34680272022`.

- PASS LF direct SHA = OTel SHA: `52c1052d55b4547ae0c1a7c5679cbcd43e801ef5fb7cdab1b8c535ca1b588d5f`.
- Fail-closed LF direct SHA = OTel SHA: `229beb9f8bc80110ea9d17ff3178e6306920600b58c9e70d8ad22816c1a6ef89`.
- Blocking code preserved: `QUEUE_NATIVE_IMAGE_REQUIRES_GOVERNED_ENVELOPE`.
- Sensitive content export: false; external export: false.
- Synthetic median overhead: `+0.206467 ms` over 100 measured runs + 10 warmups, fake model and in-memory exporter only.

Claim ceiling: deterministic local parity/privacy only; not production exporter/live-model throughput.

## R03-C result — Phoenix local adapter fit

Status: **PASS_WITH_LICENSE_GATE**. Technical fit: **PASS**. Commercial/license approval: **REQUIRED_SEPARATELY**.

Evidence run: `34680744141`. Tested head: `65ccbf14d6d3d1c7d14d8fa89493bbc77fe4ccc4`. Persisted receipt: `R03C_PHOENIX_LOCAL_FIT_REPORT.json`, SHA-256 `739e08444287c107e808a420fc8c3ee0a18cd405946a11e29b04eafae377c4c7`.

Phoenix ran only as an ephemeral self-hosted service on `127.0.0.1:6006` with product telemetry disabled. No external SaaS export, model network call or production effect occurred.

The LF result was exact-hash identical before Phoenix, through OTel/Phoenix, and after writing a Phoenix annotation:

`52c1052d55b4547ae0c1a7c5679cbcd43e801ef5fb7cdab1b8c535ca1b588d5f`

Checks passed:
- trace ingested/retrieved;
- safe LF metadata/hashes retrieved;
- raw sensitive content absent;
- raw input/output attributes absent;
- observational LF evaluator annotation written/retrieved;
- annotation did not mutate LF result;
- external SaaS export false.

Local isolated round trips: LF execution + local export `29.357410 ms`; span retrieval `47.790945 ms`; annotation write/read `36.188432 ms`. These are not production throughput benchmarks.

Pins used:
- Phoenix Server `20.9.0`, recorded license `Elastic-2.0`;
- Phoenix Client `3.5.0`, recorded license `Apache-2.0`;
- OpenTelemetry `1.44.0`.

The technical PASS does **not** authorize Phoenix Server for commercial or production use. R03-C also exposed a materially larger dependency surface than core OTel, so the full server must not be added to LF runtime requirements merely because local fit passed.

## Current recommendation

1. Adopt OTel traces/metrics behind `LF_TELEMETRY_PORT`.
2. Keep LF certification/evidence canonical and independent.
3. Treat Phoenix as optional DEV/EVAL observability only until further review.
4. Keep full Phoenix Server out of LF runtime requirements until license/dependency review closes.
5. Preserve OTLP portability so the backend remains replaceable.

## Next bounded gate — R03-D

`ADOPT-R03-D — PHOENIX_LICENSE_DEPENDENCY_ADOPTION_COST`

Read-only evaluation of license/commercial approval, dependency/supply-chain footprint, operational weight, full-server vs client/OTLP alternatives, and whether Phoenix belongs only in development/evaluation tooling.

No production adoption is authorized by R03-D analysis alone. Separately, LangGraph `R02-E` remains blocked until the final stable S26 freeze.
