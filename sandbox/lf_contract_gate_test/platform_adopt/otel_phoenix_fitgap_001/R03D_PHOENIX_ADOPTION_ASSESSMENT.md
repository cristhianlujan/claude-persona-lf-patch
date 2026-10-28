# R03-D — Phoenix License, Dependency Footprint & Adoption Cost

Strategy: `LF_PLATFORM_ADOPT_FIRST_20260912`  
Gate: `ADOPT-R03-D`  
Mode: `READ_ONLY_ARCHITECTURE_ASSESSMENT`  
Production/runtime mutation: **none**

## Decision

`PHOENIX_DEV_EVAL_OPTIONAL_SEPARATE_SERVICE_NOT_LF_RUNTIME_DEPENDENCY`

OpenTelemetry remains the LF technical telemetry standard. Phoenix has passed the local technical-fit gate, but the full Phoenix Server should **not** be installed inside the LF application/runtime environment.

If Phoenix is adopted later, place it as a replaceable, separately deployed DEV/EVAL observability backend behind OTLP. Keep the LF runtime dependent only on the governed OpenTelemetry telemetry port/export path. Use `arize-phoenix-client` only in tooling/offline evaluator/admin flows that actually need Phoenix API operations such as annotations, datasets or experiments.

## Evidence already proven

R03-C established:
- Phoenix local technical fit: `PASS_WITH_LICENSE_GATE`;
- exact LF result/hash parity before, during and after Phoenix annotation;
- annotation is observational only;
- no raw sensitive content retrieved;
- no external SaaS export;
- no model network call;
- no production effect.

Evidence run: `34680744141`.  
R03-C report SHA-256: `739e08444287c107e808a420fc8c3ee0a18cd405946a11e29b04eafae377c4c7`.

## 1. License gate

Phoenix Server 20.9.0 is distributed under Elastic License 2.0 (ELv2). Phoenix's own self-hosting documentation states that self-hosting on infrastructure controlled by the user is permitted. ELv2 nevertheless has restrictions, including the prohibition on providing substantial Phoenix functionality to third parties as a hosted/managed service.

The Python `arize-phoenix-client` 3.5.0 is separately published under Apache-2.0.

### LF decision

- Internal/self-hosted engineering use: **license-compatible candidate**, subject to LF's normal legal/commercial approval process.
- Exposing a substantial Phoenix UI/API as a customer-facing managed service: **not approved by this architecture gate**; requires specific legal review/licensor clarification.
- Do not treat Phoenix Server as Apache/MIT merely because its client is Apache-2.0.

This document is an engineering/license-risk gate, not legal advice.

## 2. Dependency footprint

The full `arize-phoenix` package is the entire Phoenix platform. Its published wheel is about 7.8 MB, while `arize-phoenix-client` 3.5.0 is about 264 KB.

The isolated R03-C CI installation of Phoenix Server resolved a broad dependency graph including, among others:
- Anthropic and OpenAI SDKs;
- Google GenAI and Google Auth;
- boto3 / botocore;
- Pydantic AI / Pydantic Graph;
- pandas, NumPy, SciPy, scikit-learn, PyArrow;
- FastMCP / MCP;
- SQLAlchemy / Alembic / aiosqlite;
- gRPC and OpenTelemetry exporters/instrumentation;
- Phoenix eval, OTel and OpenInference packages;
- authentication, LDAP and keyring-related packages.

This dependency set is reasonable for a standalone observability/evaluation platform, but it is disproportionate for the LF execution runtime whose only requirement is to emit governed telemetry.

### LF decision

`arize-phoenix` full server: **FORBIDDEN_IN_LF_RUNTIME_REQUIREMENTS_PENDING_EXPLICIT_EXCEPTION**.

Running Phoenix as a separate service isolates:
- dependency resolution conflicts;
- CVE/supply-chain patch cadence;
- memory/runtime footprint;
- application cold-start/install cost;
- optional provider SDK churn;
- licensing boundary.

## 3. Operational placement

Recommended topology:

```text
LF APPLICATION / AGENTS
        |
        | governed metadata + hashes only
        v
LF_TELEMETRY_PORT
OpenTelemetry SDK
        |
        | OTLP
        v
OTEL COLLECTOR
        |
        +---------------------> standard backend(s)
        |
        +---------------------> PHOENIX (optional DEV/EVAL)
                                  separate service/container
                                          |
                                 Phoenix Client only in
                                 evaluator/admin tooling
```

The OpenTelemetry Collector is vendor-neutral and can batch, retry, filter/redact and route telemetry to one or more backends. This keeps Phoenix replaceable and prevents a backend-specific client from becoming an LF core dependency.

## 4. Capability placement

| Capability | LF runtime | OTel/Collector | Phoenix separate service | Phoenix client tooling |
|---|---|---|---|---|
| emit traces/metrics | metadata/hash projection only | receive/process/route | observe | no |
| retry/batch/export | no custom backend logic | yes | backend receiver | no |
| prompt/content capture | OFF | filter/redact | OFF by default | no raw LF content |
| trace exploration | no | no | yes | optional |
| evaluator result visualization | LF result remains canonical | transport only | observational copy | write/read copy |
| datasets/experiments | no | no | optional | optional |
| LF PASS authority | **LF only** | no | no | no |
| LF evidence/replay | **LF only** | no | no | no |

## 5. Cost / benefit

### Benefits Phoenix adds
- AI/agent-specific trace exploration;
- experiment/dataset workflows;
- evaluation overlays;
- fast engineering diagnostics around LLM/agent behavior.

### Costs Phoenix adds
- ELv2 commercial/license governance for the server;
- materially larger dependency and patch surface if installed as Python package;
- separate state/database/service operations;
- another UI/backend to secure, back up and maintain;
- risk of developers confusing an observational Phoenix score with LF certification.

### Net

Phoenix is valuable enough to keep as an optional DEV/EVAL tool, but not differentiated enough to justify coupling LF runtime to the full platform.

## 6. Alternatives and portability

Do not choose a tracing backend as part of the LF semantic architecture. OTel/OTLP must remain the contract.

That permits later routing to Phoenix, Jaeger, Tempo, a commercial OTel backend, or multiple backends without changing Cards, Authority, Typed Context, runtime contracts or LF evidence.

Phoenix remains attractive specifically for AI eval/experiment UX, not because LF needs Phoenix to emit telemetry.

## Final R03-D verdict

| Dimension | Verdict |
|---|---|
| OpenTelemetry core | **ADOPT** |
| OTel Collector boundary | **ADOPT AS TARGET ARCHITECTURE** |
| Phoenix local technical fit | **PASS** |
| Phoenix Server inside LF runtime | **NO** |
| Phoenix separate DEV/EVAL backend | **YES, OPTIONAL** |
| Phoenix client in LF core | **NO** |
| Phoenix client in evaluator/admin tooling | **OPTIONAL** |
| Phoenix as LF authority/evidence source | **FORBIDDEN** |
| Production Phoenix rollout | **NOT AUTHORIZED** |
| Legal/commercial sign-off | **REQUIRED BEFORE PRODUCTION USE** |

## Next gate

No additional Phoenix implementation is required before S26 finishes. The next high-value runtime gate remains LangGraph `R02-E` against the final stable S26 freeze.

A future bounded `R03-E` may validate a separately deployed OTel Collector + backend in a non-production environment if LF decides to operationalize telemetry. That gate must keep content capture OFF and preserve exact LF output semantics.
