# S26-HP-001 — Evidence Tables for Claude / GPT

## Frozen project identity

| Field | Value | Authority |
|---|---|---|
| Project | `S26` | isolation manifest |
| Test | `S26-HP-001` | isolation manifest |
| Frozen base branch | `lf/s26-hp001-base-db88d` | Git ref |
| Frozen base SHA | `db88d66dc2b79fb081748fb4a86d4057f30adb18` | Git commit |
| Candidate branch | `lf/s26-hp001-isolated-20260909` | PR #633 head |
| Candidate SHA authority | `GITHUB_EVENT_HEAD_SHA` | event payload / branch checkout |
| Merge-ref usable as candidate SHA | `NO` | AUD-025 isolation rule |
| `main` drift invalidates test | `NO` | observational-only main rule |
| ZIP delivery | `NO` | owner instruction |

## Exact input

| Field | Value |
|---|---|
| Input path | `sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/input.txt` |
| SHA-256 | `fdfb12f2c8c5313fef5152e1f6b6689ccae78ed94170358cf065bb02649135a1` |
| Exact text | `Diseña una pantalla para un marketplace de servicios. Debe tener un encabezado con buscador, categorías principales, una sección de servicios destacados y tarjetas que muestren título, proveedor, precio y una llamada a la acción. El diseño debe ser claro, profesional y fácil de navegar. Entrega una especificación estructurada lista para que otro agente implemente la pantalla.` |

## Exact output artifact

| Field | Value |
|---|---|
| Output path | `sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/manual_profile_output.json` |
| SHA-256 | `712fcb036a4db6ded06615f0ec1c4dd7b9d475fa6208f5b9fc72c7688b9f01d6` |
| Producer | `GPT-5.6 Sol` |
| Execution mode | `CURRENT_CHAT_MANUAL_PROFILE_RUN` |
| Profile | `ui_architect` |
| Output contract | `UI_PRODUCTION_SPEC_V6` |
| Card resolution | `NO_CARD_GOVERNED` |
| Runtime auto-model used | `NO` |
| Weight acquisition | `NO` |
| Paid fallback | `NO` |
| Production effect | `NO` |

## Material output readback

| Requirement | Output evidence | Status |
|---|---|---|
| Header with search | `header_search` | PASS |
| Main categories | `category_navigation` | PASS |
| Featured services | `featured_services` | PASS |
| Service cards | `service_cards` + `service_card_template` | PASS |
| Card title | `service_title` / `title` field | PASS |
| Provider | `service_provider` / `provider` field | PASS |
| Price | `service_price` / `price` field | PASS |
| CTA | `service_cta` / `call_to_action` field | PASS |
| Clear | `design_intent=clear` | PASS |
| Professional | `design_intent=professional` | PASS |
| Easy to navigate | `design_intent=easy_to_navigate` | PASS |
| Implementation-ready | `STRUCTURED_SPEC_READY_FOR_NEXT_AGENT` | PASS |
| No fabricated records/prices/routes | `DATA_BOUND` + risk controls | PASS |

## A→J stage matrix

| Stage | Result | Evidence |
|---|---|---|
| Gate 0 — isolation | PASS | `test_s26_hp001_isolation.py` |
| A — exact input | PASS | `input.txt` + SHA-256 |
| B — EKB | PASS | schema-first control-plane readback, active applicable codes |
| C — Card | PASS | `NO_CARD_GOVERNED`; LF card requires MarketPlace LF context and runtime is disabled |
| D — Authority | PASS | user requirement + profile contract + output schema + recipient boundary |
| E — typed context | PASS | `LF_RUNTIME_TYPED_CONTEXT_V1`, no adapters, no schema synthesis |
| F — profile execution | PASS | manual current-chat run, explicitly not automatic runtime proof |
| G — contract shape | PASS | canonical UI validator + Composer boundary validator |
| H — material requirements | PASS | semantic material checker + negative mutations |
| I — evidence | PASS | this table + `evidence_index.json` |
| J — deterministic replay | REQUIRED ON FINAL HEAD | `test_s26_hp001_replay.py` |

## Pre-evidence exact-head proof

| Evidence | ID / value | Result |
|---|---|---|
| Candidate head | `3c1e6528e7b405261aab07474cff6048819b94bf` | observed |
| Validate LF Packs | run `34433140044` | SUCCESS |
| Profile Runtime V3 tests | `32` | executed |
| Profile Runtime V3 failures | `0` | PASS |
| HP001 isolation test | exact-head | PASS |
| HP001 output F→H test | exact-head | PASS |
| Output negative controls | `5/5` | PASS |
| lf-contract push | run `34433140001` | event-specific evidence; final readback required |
| lf-contract PR | run `34433143278` | event-specific evidence; final readback required |

## Errors found and disposition

| Error / risk | Origin | Disposition | Status |
|---|---|---|---|
| Shared S30 workflow treated unrelated S26 edits as S30 mutation | cross-lane | scoped S30 block guard in PR #626 | FIXED |
| S26-E snapshot digest was self-referential | S26-E | removed digest from payload | FIXED |
| S26-E self-test digest pin became stale | S26-E | repinned to refreshed snapshot | FIXED |
| B and E lacked one-head proof | S26-B/E | combined at frozen source `db88d66...` and 5/5 green | FIXED |
| Parallel `main` moves could stale test identity | cross-project | unique frozen base + unique head + PR #633; main observational only | FIXED FOR HP001 |
| Merge-ref vs branch-head ambiguity | CI evidence | event head and checkout SHA recorded separately | FIXED FOR HP001 |
| Temporary Python test used JSON `true` literal | HP001 pre-commit | corrected to Python `True` before branch update; no CI run consumed | FIXED |
| Independent semantic reviewer not yet executed | HP001 review | separate immutable candidate review required | OPEN |

## Review ceiling

| Gate | Status |
|---|---|
| Deterministic / structural Happy Path | pending final replay commit CI |
| Independent semantic review | NOT_EXECUTED |
| Overall S26 Golden | NOT_GOLDEN |

No independent reviewer may infer PASS from this producer table alone. Resolve the frozen candidate SHA, read the exact input/output bytes, and issue a separate reviewer receipt.
