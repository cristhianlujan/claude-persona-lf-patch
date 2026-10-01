# M0.5 — Responsibility Block Map

**Plan:** `IG_CURATOR_VALIDATOR_REFACTOR_V2`  
**Unit:** `M0.5` / `PAULO-113` / L4  
**Purpose:** classify the responsibility of `classify_v1/v2` and `semantic_probe_v1/v2/v3`, and map cached variants without changing runtime behavior.  
**Git base:** `6af74e930a98eaa4797a821539cdc473c3cc4dc9`  
**Data companion:** `docs/input-governance/responsibility_block_map_v1.json`  
**Data SHA-256 before Git publication:** `15cae7e8651761485eecfef8c61277ada87ce4d4165f97cead67962c3a6f270b`

## Scope and authority

This is a documentation/data-only unit. No function, migration, runtime, readiness run, assessment, gap proposal, or `lf_ops` row is modified.

The unit source pack requires R16 Git-first. R17 is not triggered because M0.5 does not change or execute runtime.

The preferred read model was refreshed immediately before publication. No drift was observed versus the prior technical readback.

## Responsibility classes

| Class | Meaning |
|---|---|
| `FACT` | Direct canonical/source observation or deterministic structural read. |
| `POLICY` | Governance/authority/applicability rule controlling admissibility or applicability. |
| `HEURISTIC` | Regex/category/rule-probe bootstrap inference; not canonical semantic authority. |
| `SEMANTIC` | Domain resolver translating canonical facts/relations into a family conclusion. |
| `READINESS` | Stage readiness, severity and blocker computation. |
| `ORCHESTRATION` | Dispatch, delegation, fallback/control flow and composition. |
| `PERSISTENCE` | Durable mutation/write. |
| `EVIDENCE` | Probe payload, source refs, rationale, hashes and readback envelope. |

`PERSISTENCE` is intentionally absent from the five classified base functions: static readback found no `INSERT`, `UPDATE` or `DELETE`.

## Refreshed base fingerprints

| Function | md5(prosrc) | length | WHEN |
|---|---:|---:|---:|
| `fn_input_governance_bootstrap_classify_v1` | `d6fae7a979b9c01fa348886c216856ea` | 18163 | 57 |
| `fn_input_governance_bootstrap_classify_v2` | `824147e6bc9960961016009f17fa4430` | 11799 | 2 |
| `fn_input_governance_semantic_probe_v1` | `0abfbb70b386a317d00167d8132a43cf` | 11202 | 7 |
| `fn_input_governance_semantic_probe_v2` | `c2832adc0b4d9e510b83bf4e3e533256` | 3607 | 0 |
| `fn_input_governance_semantic_probe_v3` | `d5b342e81c8bee8558fed1116c358053` | 63323 | 98 |

## Cached fingerprints

| Function | md5(prosrc) | length | WHEN |
|---|---:|---:|---:|
| `fn_input_governance_bootstrap_classify_v1_cached_v1` | `3c07f4363552cb8ad35664dbf0de54c3` | 18098 | 57 |
| `fn_input_governance_bootstrap_classify_v1_cached_v2` | `260b91965d940e062d2fcd6681794d3a` | 18116 | 57 |
| `fn_input_governance_bootstrap_classify_v2_cached_v1` | `d2069b41cec7fe5f540dfcfc9076172b` | 11817 | 2 |
| `fn_input_governance_bootstrap_classify_v2_cached_v2` | `d2f941f1f755fc45bb6d3fbf9999242e` | 11770 | 2 |
| `fn_input_governance_semantic_probe_v1_cached_v1` | `dc6dca92f3a5f877415985fa7cba4027` | 11137 | 7 |
| `fn_input_governance_semantic_probe_v2_cached_v1` | `05d39a40acfbe0619b6c32253bf45d97` | 3560 | 0 |
| `fn_input_governance_semantic_probe_v3_cached_v1` | `03e79e878c653c1d50b1b145d72f4cf9` | 62530 | 98 |

## `fn_input_governance_bootstrap_classify_v1`

High-level flow:

`ORCHESTRATION → POLICY → FACT → POLICY(N/A) → family dispatch → HEURISTIC fallback → READINESS → EVIDENCE`

Stable fixed blocks:

- `C1.ORCH.INIT` lines 1–42 — `ORCHESTRATION`
- `C1.POLICY.UNIVERSE` lines 43–49 — `POLICY`
- `C1.FACT.CONTEXT` lines 50–67 — `FACT`
- `C1.POLICY.NA` lines 68–82 — `POLICY`
- `C1.ORCH.FAMILY_DISPATCH` lines 83–84 — `ORCHESTRATION`
- `C1.ORCH.UNHANDLED_END` lines 150–152 — `ORCHESTRATION`
- `C1.HEUR.GENERIC_FALLBACK` lines 153–160 — `HEURISTIC`
- `C1.READINESS.STAGES` lines 161–176 — `READINESS`
- `C1.READINESS.BLOCKERS` lines 177–191 — `READINESS`
- `C1.EVIDENCE.AUGMENT` lines 192–202 — `EVIDENCE`
- `C1.ORCH.END` lines 203–204 — `ORCHESTRATION`

Family dispatch map:

| Family | Lines | Class |
|---|---:|---|
| `SCREEN_IDENTITY` | 85-87 | **FACT** |
| `OBJECTIVE_OUTCOMES` | 88-90 | **FACT** |
| `FIELDS` | 91-92 | **FACT** |
| `VALIDATIONS` | 93-98 | **FACT** |
| `STATES` | 99-102 | **FACT** |
| `TRANSITIONS` | 103-108 | **HEURISTIC** |
| `PROFILES` | 109-109 | **FACT** |
| `PERMISSIONS` | 110-110 | **FACT** |
| `ERRORS` | 111-111 | **FACT** |
| `UI_MESSAGES` | 112-112 | **FACT** |
| `ANALYTICS` | 113-113 | **HEURISTIC** |
| `RESPONSIVE` | 114-114 | **FACT** |
| `DESIGN_SYSTEM` | 115-119 | **FACT** |
| `ASSETS_ICONS` | 120-120 | **FACT** |
| `API_DATA_CONTRACT` | 121-121 | **SEMANTIC** |
| `DEPENDENCIES` | 122-122 | **FACT** |
| `VISUAL_EVIDENCE` | 123-123 | **FACT** |
| `EKB` | 124-124 | **POLICY** |
| `SOURCE_AUTHORITY_PROVENANCE` | 125-125 | **POLICY** |
| `FRESHNESS_INVALIDATION` | 125-125 | **POLICY** |
| `NEGATIVE_REQUIREMENTS` | 125-125 | **POLICY** |
| `CONFLICT_PRECEDENCE` | 125-125 | **POLICY** |
| `APPLICABILITY_READINESS` | 125-125 | **POLICY** |
| `CONTEXT_BUDGET_RETRIEVAL_POLICY` | 126-126 | **POLICY** |
| `ROLLOUT_PRODUCTION_GATES` | 127-127 | **POLICY** |
| `ACTIONS` | 128-128 | **HEURISTIC** |
| `ROUTING_NAVIGATION` | 129-129 | **HEURISTIC** |
| `SESSION` | 130-130 | **HEURISTIC** |
| `RATE_LIMIT` | 131-131 | **HEURISTIC** |
| `TIMEOUT_RETRY` | 132-132 | **HEURISTIC** |
| `SECURITY` | 133-133 | **HEURISTIC** |
| `MFA_OTP_SSO` | 134-134 | **HEURISTIC** |
| `PRIVACY_PII` | 135-135 | **HEURISTIC** |
| `AUDIT` | 136-136 | **HEURISTIC** |
| `OBSERVABILITY` | 137-137 | **HEURISTIC** |
| `PERFORMANCE` | 138-138 | **HEURISTIC** |
| `THEME_LIGHT_DARK_SYSTEM` | 139-139 | **FACT** |
| `FORCED_COLORS_CONTRAST` | 140-140 | **HEURISTIC** |
| `REDUCED_MOTION` | 141-141 | **HEURISTIC** |
| `ACCESSIBILITY` | 142-142 | **HEURISTIC** |
| `LOADING_EMPTY_ERROR_STATES` | 143-143 | **HEURISTIC** |
| `IDEMPOTENCY_CONCURRENCY` | 144-144 | **HEURISTIC** |
| `FEATURE_FLAGS` | 145-145 | **HEURISTIC** |
| `TESTING_OBLIGATIONS` | 146-146 | **HEURISTIC** |
| `BROWSER_PLATFORM` | 147-147 | **HEURISTIC** |
| `I18N_FORMATS` | 148-148 | **HEURISTIC** |
| `RUNTIME_CONFIG` | 149-149 | **HEURISTIC** |

All 47 canonical families are present. The five governance families sharing physical line 125 are represented as five logical family blocks against the same source line; they share a class (`POLICY`), so this does not create a dual-class block.

## `fn_input_governance_bootstrap_classify_v2`

- `C2.ORCH.BASE` 1–23 — `ORCHESTRATION`
- `C2.SEM.DESIGN_SYSTEM` 24–69 — `SEMANTIC`
- `C2.SEM.API_DATA_CONTRACT` 70–125 — `SEMANTIC`
- `C2.SEM.MFA_OTP_SSO` 126–189 — `SEMANTIC`
- `C2.ORCH.SEMANTIC_DELEGATE` 190–194 — `ORCHESTRATION`
- `C2.SEM.APPLY_RESULT` 195–202 — `SEMANTIC`
- `C2.READINESS.APPLY` 203–235 — `READINESS`
- `C2.EVIDENCE.HASH` 236–237 — `EVIDENCE`
- `C2.ORCH.END` 238–239 — `ORCHESTRATION`

This function is the explicit seam where bootstrap classification delegates unresolved applicable families to `semantic_probe_v3`, then normalizes stage authority.

## `fn_input_governance_semantic_probe_v1`

Family resolvers are owned by `SEMANTIC`; canonical reads inside each resolver are its input facts rather than a second owning responsibility.

- `P1.ORCH.GATE` 1–39 — `ORCHESTRATION`
- `P1.SEM.I18N` 40–48 — `SEMANTIC`
- `P1.SEM.LOADING` 49–59 — `SEMANTIC`
- `P1.SEM.SESSION` 60–126 — `SEMANTIC`
- `P1.SEM.RUNTIME_CONFIG` 127–155 — `SEMANTIC`
- `P1.SEM.SECURITY` 156–179 — `SEMANTIC`
- `P1.SEM.TIMEOUT_RETRY` 180–204 — `SEMANTIC`
- `P1.SEM.ASSETS_ICONS` 205–242 — `SEMANTIC`
- `P1.ORCH.END` 243 — `ORCHESTRATION`

## `fn_input_governance_semantic_probe_v2`

- `P2.ORCH.BASE` 1–22 — `ORCHESTRATION`
- `P2.SEM.ROUTING` 23–70 — `SEMANTIC`
- `P2.SEM.RESPONSIVE` 71–97 — `SEMANTIC`
- `P2.ORCH.END` 98–101 — `ORCHESTRATION`

## `fn_input_governance_semantic_probe_v3`

This function contains the clearest responsibility mixing in the current implementation. The logical pattern is explicitly split as:

`FACT → SEMANTIC → READINESS → EVIDENCE → ORCHESTRATION/FALLBACK`

The line anchors below locate the first semantic return, stage payload, evidence probe and fallback. A family may have more than one outcome payload; the data file records the observed counts.

| Family | Resolver span | First return | First stage status | First probe payload | Fallback |
|---|---:|---:|---:|---:|---:|
| `SESSION` | 34-167 | 96 | 108 | 128 | 165 |
| `SECURITY` | 168-242 | 193 | 206 | 229 | 240 |
| `TIMEOUT_RETRY` | 243-367 | 296 | 309 | 329 | 365 |
| `RATE_LIMIT` | 368-488 | 411 | 417 | 427 | 486 |
| `OBSERVABILITY` | 489-606 | 530 | 545 | 567 | 604 |
| `RUNTIME_CONFIG` | 607-699 | 649 | 662 | 685 | 697 |
| `ANALYTICS` | 700-858 | 782 | 795 | 818 | 856 |
| `FORCED_COLORS_CONTRAST` | 859-922 | 887 | 897 | 911 | 920 |
| `REDUCED_MOTION` | 923-986 | 951 | 961 | 975 | 984 |
| `AUDIT` | 987-1106 | 1045 | 1054 | 1067 | 1104 |
| `ACCESSIBILITY` | 1107-1162 | 1127 | 1133 | 1146 | 1160 |
| `FIELDS` | 1163-1168 | — | — | — | 1166 |
| `VALIDATIONS` | 1169-1192 | 1180 | 1183 | 1185 | 1190 |
| `ROUTING_NAVIGATION` | 1193-1217 | 1207 | 1210 | 1212 | 1215 |
| `TRANSITIONS` | 1218-1252 | 1242 | 1245 | 1247 | 1250 |
| `MFA_OTP_SSO` | 1253-1284 | 1275 | 1278 | 1280 | 1283 |
| `ACTIONS` | 1286-1407 | 1387 | — | — | 1405 |

Special cases:

- `FIELDS` delegates to `fn_input_governance_field_reference_probe_v1`.
- `MFA_OTP_SSO` ends at line 1284.
- `ACTIONS` begins at line 1286 and occupies the final resolver section.
- The map deliberately separates readiness/evidence as logical responsibilities even when PL/pgSQL places several JSON fields in one physical return expression.

## Cached parity map

| Source | Cached | Physical diff lines | Responsibility verdict | Explanation |
|---|---|---:|---|---|
| `fn_input_governance_bootstrap_classify_v1` | `fn_input_governance_bootstrap_classify_v1_cached_v1` | 1 | **SAME_RESPONSIBILITY_MAP** | p_graph injection replaces canonical graph fetch |
| `fn_input_governance_bootstrap_classify_v1` | `fn_input_governance_bootstrap_classify_v1_cached_v2` | 2 | **SAME_RESPONSIBILITY_MAP** | p_graph plus cached N/A authority substitution |
| `fn_input_governance_bootstrap_classify_v2` | `fn_input_governance_bootstrap_classify_v2_cached_v1` | 1 | **SAME_RESPONSIBILITY_MAP** | cached v1 classifier delegation |
| `fn_input_governance_bootstrap_classify_v2` | `fn_input_governance_bootstrap_classify_v2_cached_v2` | 3 | **SAME_RESPONSIBILITY_MAP** | cached classifier/graph/semantic delegation substitutions |
| `fn_input_governance_semantic_probe_v1` | `fn_input_governance_semantic_probe_v1_cached_v1` | 1 | **SAME_RESPONSIBILITY_MAP** | p_graph injection |
| `fn_input_governance_semantic_probe_v2` | `fn_input_governance_semantic_probe_v2_cached_v1` | 2 | **SAME_RESPONSIBILITY_MAP** | cached v1 probe plus p_graph injection |
| `fn_input_governance_semantic_probe_v3` | `fn_input_governance_semantic_probe_v3_cached_v1` | 1025 | **DIVERGENT_TEXT_SAME_RESPONSIBILITY_SHAPE** | 25 physical lines shorter; same 17 family sequence; same referenced lf_ops objects except cached helper substitutions; structural counters stage_statuses=22, stage_blockers=22, resolution_contract=23, return_payload=23, handled=25 in both. This map does not claim runtime-output parity. |

The large textual difference in `semantic_probe_v3_cached_v1` is **not** treated as textual parity. It is explicitly flagged as divergent. Structural readback shows:

- same 17-family sequence;
- same referenced `lf_ops` objects, except expected cached-helper substitutions;
- `stage_statuses`: 22 vs 22;
- `stage_blockers`: 22 vs 22;
- `resolution_contract`: 23 vs 23;
- return payload markers: 23 vs 23;
- `handled`: 25 vs 25.

M0.5 therefore asserts **responsibility-map parity only**, not runtime-output parity.

## Negative validation

| Check | Result |
|---|---:|
| Canonical families | 47 |
| Present in `classify_v1` | 47/47 |
| Missing families | 0 |
| Base functions classified | 5/5 |
| Cached variants mapped | 7/7 |
| Unclassified logical blocks | 0 |
| Dual-class logical blocks | 0 |
| Persistence blocks | 0 |
| Runtime parity claimed | No |

## Architectural implication

The current implementation has a clean conceptual seam available for the refactor:

1. canonical reads belong in `FACT`;
2. policy/applicability belongs in `POLICY`;
3. regex/rule probes remain bootstrap `HEURISTIC`;
4. family resolution belongs in `SEMANTIC`;
5. stage gates belong in `READINESS`;
6. dispatch belongs in `ORCHESTRATION`;
7. evidence construction belongs in `EVIDENCE`;
8. none of these classifier/probe functions should own `PERSISTENCE`.

This map is descriptive AS-IS evidence for later refactor units; it does not itself modify the implementation.
