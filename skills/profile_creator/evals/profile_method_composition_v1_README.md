# Profile Updater — method composition consumer (candidate)

**Status:** Source-only shadow adapter, not a new capability selector. Does not activate Profile Updater, update profiles or modify any Supabase method authority.

Uses the existing canonical, domain-agnostic provider `sandbox/lf_contract_gate_test/transversal_assets/capability_selector/capability_selector_v1.py` (Git blob `d0624beacb1ee68b349bfa23a274b52c92d1c9aa`; CAPABILITY_SELECTOR 1.0.0). Must not replace the provider or independently promote selected methods.

The upstream `PROFILE_ASSESSMENT` supplies typed evidence-bound signals. Method records and scope applicability are supplied by the resolved `METHOD_PACK_REGISTRY` catalog; caller must independently verify authority, provenance and currentness. This adapter checks caller declarations for basic completeness but does **not** independently attest any source; a boolean flag is not verification. Output remains advisory and explicitly disables method execution/profile writes/runtime activation.

Inputs: `assessment{profile_slug,signals[{type,value,evidence_ref,evidence_state}]}`, `method_registry{registry_id,provider_verified,source_ref,methods[]}`, and `policy{fallback_capabilities[]}`. Experimental signals may use `EXERCISE_SUPPLIED`, clearly distinguished from `VERIFIED`. Methods intended for this shadow adapter have `availability_state=EXPERIMENTAL_NOT_ADMITTED`, `selection_lane=SHADOW_ONLY`, `auto_select=false`, and `execution_permission=false`. A truly empty composition requires explicit supported decision `NO_ADDITIONAL_CAPABILITY_NEEDED`, not merely no signals.

Run from repository root: `python -m skills.profile_creator.evals.test_profile_method_composition_v1`.

**Evidence:** 12 test cases / 9 negative controls, using synthetic registry and manually derived signals. This proves consumer selection behavior only, not natural-language extraction, external catalog readback, user outcome uplift, provider attestation, or production suitability.

**Pending next lot:** bind trusted `PROFILE_ASSESSMENT` and governed method registry, validate actual catalog schema and runtime source projection, run independent behavioral holdout and Train admission. Do not add a parallel engine or modify canonical `CAPABILITY_SELECTOR`.
