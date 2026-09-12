# Input Governance Agent v5.5 — Claude audit handoff

Date: 2026-08-18

## Purpose

This document is an audit navigation aid, **not** source authority. Claude must independently read Supabase and GitHub, recompute the checks, and report divergences. Do not accept this file as evidence of PASS by itself.

## Canonical Supabase target

- Project ref: `mhwmirqcgxxukpctffuv`
- Governance schema: `programacion`
- Functional sources: `lf_ops`
- Design sources: `lf_design`
- EKB: `transversal`

## Current candidate expected from independent readback

- Agent: `INPUT_GOVERNANCE_AGENT`
- Agent root state: `draft`
- Agent version id: `19`
- Version code: `v0.5-input-readiness-api-contract-sufficiency-r1-stage-gates-candidate`
- Version state: `candidate`
- Contract: `INPUT_READINESS_CONTRACT`
- Contract revision: `5.5`
- Fail closed: `true`
- Negative tests: `24`
- Production / Golden / active promotion: **not authorized**

## Current terminal runs expected

| Screen | pantalla_id | run_id | Expected status | Expected current | Families | Validator PASS |
|---|---:|---:|---|---|---:|---:|
| B2B-AUTH-001 | 51 | 60 | COMPLETED | true | 47 | 47 |
| B2B-AUTH-002 | 52 | 62 | COMPLETED | true | 47 | 47 |
| B2B-AUTH-003 | 53 | 58 | COMPLETED | true | 47 | 47 |
| B2B-AUTH-004 | 54 | 59 | COMPLETED | true | 47 | 47 |
| B2B-AUTH-005 | 55 | 61 | COMPLETED | true | 47 | 47 |

Expected independent Validator recheck: **305 assertions PASS / 0 FAIL**.

Expected module health:

- module: `B2B_AUTENTICACION`
- health contract: `INPUT_GOVERNANCE_MODULE_HEALTH_V1`
- healthy screens: `5/5`
- `health_pass=true`
- expected health SHA at handoff creation: `e3ec76e86262977519fde95cdba0c611989917637708664f701fcdd1c4e18c3c`

The health SHA is time/source sensitive; recompute rather than trusting the literal value.

## Required adversarial checks

Claude should independently verify at least:

1. The five v19 runs are `COMPLETED` and current.
2. Their predecessors 53–57 are **not current** after terminal supersession.
3. `fn_input_context_manifest()` rejects superseded/stale runs.
4. `fn_input_freshness_delta()` marks a terminal predecessor as stale with lineage semantics.
5. The five current runs each contain exactly 47 family assessments and 47 Validator PASS receipts.
6. Validator assertions are source-derived, relevant to the family, and all re-evaluate PASS against current pinned evidence.
7. Curator and Validator identities/components remain independent.
8. Applicability invariants hold.
9. Stage hierarchy holds: Implementation READY requires Story READY; QA READY requires Implementation READY; Production READY requires QA READY.
10. `DESIGN_SYSTEM` does not become Implementation READY from generic Design System rules alone.
11. A `component_token_id` does not hide `PENDING_VISUAL_COMPONENT` semantic gaps.
12. `API_DATA_CONTRACT` does not become Implementation READY from descriptive API prose without a resolvable operation/schema authority.
13. JIT retrieval only resolves handles emitted by the current Context Manifest.
14. Context manifests embed pins/handles but not primitive token values, runtime secrets, or canonical-source dumps.
15. No candidate/Validator self-authority is accepted.

## Readback queries

Use read-only queries. Suggested entry points:

```sql
select a.id,a.agente_codigo,a.estado
from programacion.agentes a
where a.agente_codigo='INPUT_GOVERNANCE_AGENT';

select v.id,v.version_codigo,v.estado,v.supersedes_version_id
from programacion.versiones_agente v
join programacion.agentes a on a.id=v.agente_id
where a.agente_codigo='INPUT_GOVERNANCE_AGENT'
order by v.id desc;

select c.id,c.version_id,c.contrato_codigo,c.fail_closed,c.estado,
       c.especificacion->>'contract_revision' as contract_revision,
       jsonb_array_length(c.especificacion->'negative_tests') as negative_test_count
from programacion.contratos c
where c.version_id=19
order by c.contrato_codigo;

select r.id,r.version_id,r.pantalla_id,r.supersedes_run_id,r.status,
       programacion.fn_input_readiness_run_is_current(r.id) as is_current,
       r.source_snapshot_sha256,r.validator_identity
from programacion.input_readiness_runs r
where r.id between 53 and 62
order by r.id;

select run_id,count(*) as families,
       count(*) filter (where validator_outcome='PASS') as validator_pass
from programacion.input_family_assessments
where run_id in (58,59,60,61,62)
group by run_id
order by run_id;

select programacion.fn_input_governance_module_health(19,'B2B_AUTENTICACION');

select programacion.fn_input_stage_gate_summary(x.run_id)
from (values (60),(62),(58),(59),(61)) x(run_id);

select programacion.fn_input_freshness_delta(60);
select programacion.fn_input_freshness_delta(53);
```

## GitHub/Supabase synchronization warning

At handoff creation, Supabase contains the authoritative Input Governance migrations through `20260818185300_input_governance_v55_freshness_lineage_semantics`.

The repository `cristhianlujan/claude-persona-lf-patch` main branch did **not** yet contain these 2026-08-18 Input Governance migration files. Therefore:

- Supabase is the current operational source for this candidate.
- GitHub main is not yet a complete reproducible mirror of the agent evolution.
- Audit may proceed if Claude has direct read access to the Supabase project.
- Audit from GitHub alone is **not sufficient** until migration sync is completed.

The branch containing this handoff is intentionally an audit/sync branch and must not be interpreted as production promotion.

## Expected disposition

Claude should return findings grouped as:

- P0/P1 defects
- provenance/source-authority defects
- stale/lineage defects
- semantic false-PASS risks
- Design System binding risks
- API contract sufficiency risks
- Context Manifest / retrieval risks
- reproducibility/GitHub-sync gaps
- promotion blockers

A clean result must be based on independent readback and negative probes, not on agreement with this document.
