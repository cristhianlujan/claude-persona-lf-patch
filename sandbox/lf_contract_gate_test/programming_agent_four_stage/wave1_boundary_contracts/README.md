# Programming Agent Wave 1 boundary contracts

## Procedimiento canónico de Análisis (A1–A9) — fuente preparada

- [ANALYSIS_PROCEDURE_V1.md](ANALYSIS_PROCEDURE_V1.md): secuencia operativa, responsables, salidas, transiciones, bloqueos y límites de fase.
- [analysis_procedure_v1.json](analysis_procedure_v1.json): contrato estructurado con las nueve etapas, referencias a fuentes existentes y estados permitidos.
- **Estado:** `PROCEDURE_SOURCE_COMPLETE / VALIDATION_DEFERRED`; no ejecutar caso, prueba, benchmark ni PG-01 en el lote de construcción del procedimiento. `DONE` del ledger no acredita ejecución integral del agente.
- **Separación:** el procedimiento puede construirse sin implementar ningún producto; desarrollo y testing tienen sus propios carriles.


Source-only contract bundle for the Programming Agent Analysis boundary plus Wave 1 consumers: `A1–A9`, `PG-01`, and `TST-01–TST-05`.

- **A1 / Analysis intake** produces `REQUEST_CONTEXT_V1` without Story, Functional Version, Agent Task, or solution inference.
- **A2 / Change classification** makes change type + target granularity + `L1/L2/L3` reproducible. Granularity is evidence-derived (screen/control/rule/API/data/etc.), not a fixed UI-only catalog. Specialist requirements/refs remain late-bound through `CAPABILITY_SELECTOR@CURRENT`; selection is not execution permission.
- **A3 / Targeted evidence** reuses current evidence first, queries only missing/material evidence, blocks duplicate/full-repository discovery without a trigger, and stops at minimum sufficient context.
- **A3 / Target state invariant** resolves two independent dimensions: `authority_state = EXISTING | NEW | UNKNOWN` and `implementation_state = EXISTING | NEW | UNKNOWN`. Existing canonical authority does not prove existing implementation. A predeclared LF screen may therefore be `authority_state=EXISTING` while `implementation_state=NEW`. Existing implementation requires AS-IS + explicit delta; new implementation requires bounded proof that no current implementation/reusable equivalent already satisfies the target.
- **A4 + TST-05 / Shared impact** consume one transversalized `SHARED_CHANGE_IMPACT_ANALYSIS` core from the existing inventory/dependency surfaces; Testing adds only a test-specific projection. No parallel impact engine is allowed.
- **A5 / Decision context + ADR condicional** emits `ANALYSIS_DECISION_CONTEXT_V1` and reuses `DECISION_CONTEXT_ASOF@CURRENT` plus the existing current-ADR assertion. ADR is required only for material authority/ownership, transversal capability, cross-stage contract, lifecycle/state-authority, migration/cutover, security/privacy, or runtime-topology decisions; local implementation strategy remains PG-03. Existing ADRs must be `VIGENTE`; a required new ADR yields `REQUIRES_DECISION` and cannot be self-approved by Analysis. A9 preserves the complete decision context losslessly.
- **A7 / Material Front Coverage** derives an evidence-backed open set of material fronts from impact, requirements, bindings, invariants, risk signals, specialist outputs and unresolved gaps. Every material candidate must be emitted exactly once as `REQUIRED`, `REUSE_AS_IS`, or `NOT_APPLICABLE`; absence is never interpreted as not-applicable.
- **A8 / Stop Rule** stops investigation only when the material decision is stable *and* `all_material_fronts_accounted=true`, with no unresolved question or available evidence that could still change a material decision. Front closure and scope readiness remain separate concerns.
- **A6 / Implementability** emits `IMPLEMENTABILITY_SCHEMA_V1`: typed requirements + canonical implementation bindings. Material authority/currentness/input/output/state/error/permission/side-effect obligations are explicit or blocked; Analysis specifies WHAT must be preserved/resolved, never HOW PG-03 implements it.
- **A6/A9 -> PG-01 handoff**: Analysis resolves material implementation bindings once and A9 emits a compact `PROGRAMMING_CONTEXT_SNAPSHOT_V1` inside `ANALYSIS_IMPLEMENTATION_PACKAGE_V1`. The full snapshot, including `implementability_schema`, material-front coverage and `scope_readiness[]`, must be persisted append-only through `DECISION_CONTEXT_ASOF@CURRENT`; a memory-only snapshot is invalid. Small stable facts travel as canonical ref + resolved value; large known sources travel as exact refs; dynamic/staleness-sensitive sources travel as exact ref + typed resolver. Programming may requery only on `MISSING | STALE | CONTRADICTION | SOURCE_DRIFT | MATERIAL_NEW_QUESTION`; freeform rediscovery is forbidden when a typed resolver exists.
- **A9 -> PG-01 parity** binds producer and receiver to the same `PROGRAMMING_CONTEXT_SNAPSHOT_V1` contract identity/digest. PG-01 must resolve the exact persisted context, recompute `context_sha256`, match the producer schema digest, validate every material path, and only then create a minimum worker projection. Unknown/missing material fields or lossy projection block admission.
- **PG-01 / Programming** consumes `ANALYSIS_IMPLEMENTATION_PACKAGE_V1` and its `PROGRAMMING_CONTEXT_SNAPSHOT_V1`; existing Agent Task runtime is extended at the entry boundary rather than duplicated. Admission requires target granularity plus independent authority/implementation state. `implementation_state=EXISTING` requires exact AS-IS + delta; `implementation_state=NEW` requires no-current-implementation evidence and reuse-before-build assessment.
- **PG-03 ownership** remains the place where the implementation strategy is selected from evidence. The Analysis boundary identifies the target and delta but does not preselect how the LLM/programmer must implement it.
- **TST-01 / Testing admission** supports `DESIGN_ONLY` without a candidate and `EXECUTION` with an exact frozen candidate. Neither mode requires Story identity.
- **TST-02–TST-04 / Testing design pipeline** makes change signals, risks/criticality, and quality objectives explicit and evidence-traceable using the current test-characteristic catalog and existing selectors/admission surfaces.

Target-state invariant:

```text
REQUEST
  -> classify TARGET_GRANULARITY
  -> resolve exact target
  -> AUTHORITY_STATE + IMPLEMENTATION_STATE

Example: predeclared screen, not yet programmed
  authority_state      = EXISTING
  implementation_state = NEW

implementation_state = EXISTING
  -> freeze current implementation AS-IS
  -> derive requested DELTA only

implementation_state = NEW
  -> prove no current implementation satisfies the target
  -> evaluate reuse/extension candidates before BUILD

UNKNOWN in either material dimension
  -> NEED_MORE_EVIDENCE or REQUIRES_DECISION
  -> never silently becomes a build decision
```

Design binding boundary:

```text
canonical token / asset ref = authority
current resolved value      = implementation evidence / clarity
literal value alone         != authority

Example:
  token_ref: LF_DS_V1/warm_surface
  resolved_current_value: #FDFCFA
```

Analysis closes what must be respected; PG-03 remains free to choose how to implement it.

Material front coverage:

```text
A4/A6/A7 evidence
  -> derive candidate material fronts
  -> MATERIAL_FRONT_COVERAGE_V1

Each material front:
  front_id
  front_kind
  status = REQUIRED | REUSE_AS_IS | NOT_APPLICABLE
  closure = CLOSED | BLOCKED
  source_signal_refs[]
  scope_refs[]
  authority_refs[]
  evidence_refs[]
  currentness_refs[]
  blockers[]
  reason

Rules:
- open evidence-derived front catalog; domain names alone do not select fronts
- every material candidate appears exactly once
- unknown material signal becomes an explicit BLOCKED front
- REUSE_AS_IS requires currentness evidence
- NOT_APPLICABLE requires evidence + reason
- silence/absence never means NOT_APPLICABLE
- A9 preserves the full artifact in PROGRAMMING_CONTEXT_SNAPSHOT_V1
- scope readiness remains a separate dimension
```

Scope readiness:

```text
A9 qualifies each independently executable scope:

READY
NEED_MORE_EVIDENCE
REQUIRES_DECISION
BLOCKED
NOT_APPLICABLE

Package verdict:
READY
PARTIAL_READY
NEED_MORE_EVIDENCE
REQUIRES_DECISION
BLOCKED

PARTIAL_READY is allowed only when:
- at least one scope is independently READY;
- its dependencies are closed;
- no material blocker from another scope contaminates it.

PG-01 admits only READY scopes. A blocked save/persistence scope must not stop an independent shell/layout scope, but any cross-cutting invariant or dependency that affects the supposedly ready scope blocks that scope too.
```

Implementability schema:

```text
A6 IMPLEMENTABILITY_SCHEMA_V1

requirement:
  requirement_id
  scope_refs[]
  outcome
  obligation_mode
  authority_refs[]
  evidence_refs[]
  currentness_refs[]
  input_contract_refs[]
  output_contract_refs[]
  state_contract_refs[]
  error_behavior_refs[]
  permission_refs[]
  side_effect_class
  preconditions[]
  blockers[]
  acceptance_signals[]

binding:
  binding_id
  scope_refs[]
  binding_kind
  canonical_ref
  resolved_current_value
  value_transport
  currentness_ref
  resolver_ref
  implementation_obligation
  evidence_refs[]
  blockers[]

Rules:
- material field may not disappear silently
- unknown material permission / side effect becomes blocker
- applicable state/error/input/output behavior is explicit or blocked
- canonical ref remains authority; resolved literal cannot replace it
- technical strategy stays with PG-03
```

Stop Rule:

```text
A8 may STOP only when ALL are true:

decision_stable = true
all_material_fronts_accounted = true
unresolved_decision_changing_questions[] = empty
additional_available_evidence_capable_of_changing_material_decision[] = empty

Important:
- all fronts accounted does NOT mean every front is CLOSED;
- BLOCKED / REQUIRES_DECISION fronts may remain explicit;
- missing material front always forbids STOP;
- complete front coverage with unstable decision also forbids STOP;
- curiosity search, duplicate reads and full scans without a material trigger remain forbidden.
```

Programming context handoff:

```text
A3/A4/A5 evidence
  -> A6 material bindings
  -> A9 PROGRAMMING_CONTEXT_SNAPSHOT_V1
  -> PG-01 admission
  -> PG-03 implementation strategy

small + stable + material
  -> canonical_ref + resolved_value

large + already identified
  -> exact_ref only

dynamic / staleness-sensitive
  -> exact_ref + typed_resolver

same authority_fingerprint
  -> reuse snapshot; do not rediscover

MISSING / STALE / CONTRADICTION / SOURCE_DRIFT / MATERIAL_NEW_QUESTION
  -> targeted requery through typed resolver
```

The snapshot carries facts and authority references, not technical strategy. It must not choose component structure, framework pattern, endpoint design, or internal algorithm.

Scope ↔ material-front consistency:

```text
scope_readiness[] carries material_front_refs[]
scope_front_matrix[] binds:
  scope_id
  front_id
  front_status
  front_closure
  effect_on_scope
  evidence_refs[]
  reason

Rules:
- scope/front mapping is bidirectional
- REQUIRED + BLOCKED front blocks every bound scope
- READY scope cannot contain a BLOCKS front
- REUSE_AS_IS + CLOSED may preserve the scope
- NOT_APPLICABLE never blocks the scope
- PARTIAL_READY requires every admitted READY scope to be front-clean
- PG-01 admits a READY scope only after front consistency is clean
```

A9 -> PG-01 handoff parity:

```text
A9 shared snapshot schema + schema digest
  -> persist exact snapshot / context_sha256
  -> PG-01 resolve exact context_id
  -> recompute context_sha256
  -> validate SAME snapshot schema digest
  -> validate all material paths
  -> PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1
  -> only then project MINIMUM_RELEVANT_SUBSET to workers

Fail closed:
- receiver schema digest != producer schema digest
- context digest mismatch
- missing material field
- unknown material field
- lossy material projection
- upstream snapshot mutation
```

Snapshot currentness:

```text
CURRENTNESS_AUTHORITY@CURRENT evaluates:
  context_sha256
  snapshot_schema_digest_sha256
  authority_fingerprint_sha256
  source_snapshot_sha256

decisions:
  CURRENT
  CURRENT_REBOUND
  STALE_AFFECTED
  UNKNOWN_FAIL_CLOSED

Rules:
- same current fingerprint/schema/context -> reuse; no rediscovery
- authority fingerprint change -> discard/rebuild A9 snapshot
- snapshot schema digest change -> rebuild + new receipt
- recorded as-of snapshot is immutable
- no mid-execution rebind
- global main SHA movement alone does not make the snapshot stale
- currentness uses selective affected closure
- auto-rebound requires complete dependency knowledge
- stale affected scope is blocked; UNKNOWN fails closed
- worker projection is invalidated with its parent snapshot
```

Snapshot persistence:

```text
A9 PROGRAMMING_CONTEXT_SNAPSHOT_V1
  -> DECISION_CONTEXT_ASOF@CURRENT
  -> public.fn_lf_decision_context_asof_record_v1
  -> append-only context receipt
       context_id
       decision_ref
       context_sha256
       subject_ref
       subject_version
       decided_at
       effective_at
  -> PG-01 resolves exact recorded context
  -> recomputed/resolved digest must match receipt
  -> only then project READY scopes to Programming
```

The persisted payload lives under `extensions.programming_context_snapshot`. It includes the complete `scope_readiness[]`, so a scope such as `S01_SHELL_CHROME` is auditable after the Analysis turn ends. No new snapshot table/store is introduced.

Governance:
- `REUSE_OR_TRANSVERSALIZE_BEFORE_BUILD`.
- Existing consumers stay as adapters until qualified cutover.
- Existing implementations must not be re-specified as greenfield merely because the request describes their desired behavior.
- Canonical authority existence and implementation existence are independent dimensions; never infer one from the other.
- Applicable design bindings must preserve canonical refs. Resolved hex/font/spacing values may accompany those refs but never replace them as authority.
- Analysis-resolved material context must be reused downstream while its authority fingerprint remains current; repeated source discovery without an explicit requery trigger is forbidden.
- `IMPLEMENTABILITY_SCHEMA_V1` is preserved losslessly by A9; raw prose or generic arrays cannot replace typed material obligations.
- Worker context is projected to the minimum relevant subset instead of copying the full Analysis package into every Programming step, but only after A9→PG-01 parity has been proven and the projection gets its own digest.
- Material front coverage is distinct from the Stop Rule and scope readiness: coverage answers `did Analysis account for every material front?`; the Stop Rule answers `may Analysis stop searching?`; readiness answers `which independent scopes may proceed?`. A9 additionally proves bidirectional scope↔front consistency so a blocked material front cannot disappear from a READY scope.
- Readiness is scoped: independent READY slices may proceed under `PARTIAL_READY`; blockers never get silently ignored or bypassed, and dependency closure is mandatory.
- `PROGRAMMING_CONTEXT_SNAPSHOT_V1` must have a durable append-only receipt before PG-01 admission; chat/session memory is not evidence.
- Snapshot currentness is delegated to `CURRENTNESS_AUTHORITY@CURRENT`; no parallel currentness engine or naive global-main-SHA invalidation is allowed.
- Persistence reuses `DECISION_CONTEXT_ASOF@CURRENT`; creating a parallel context/snapshot store is forbidden.
- Technical implementation strategy remains dynamic and is owned by Programming, not hardcoded by Analysis.
- No runtime or production activation, current-pointer changes, or Story Creator retirement in this PR.
- Existing unit dependencies remain authoritative.

Evidence: `lf_eventos://20315`, `lf_eventos://20333`, `lf_eventos://20334`, `lf_eventos://20335`.

Run:

```bash
python sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/validate_wave1_boundary_contracts_v1.py --self-test
```
