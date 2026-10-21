===ROLE_REPORT:AUTHORITY BEGIN===

Role: AUTHORITY
Case: PE10-IG-M107-M109-P0
Mode: READ_ONLY
Evidence: Q10–Q12, failed Q13, successful Q14
Source boundary: P0 historical EKB claims distinguished from CURRENT catalog and function-source observations.

Findings

AU1. Q10 measures 38 P0-inventoried functions against four CURRENT principals. postgres has effective catalog callability for all 38; service_role for six public functions; anon and authenticated for none. EXECUTE without schema USAGE is not effective direct callability.

AU2. Q11 extends the analysis to nine entry points and internal helpers. Among seven tested principals, service_role effectively calls four public functions; the three named programacion governance roles cannot directly execute the five examined internal functions.

AU3. Q12 identifies three SECURITY DEFINER public delegation wrappers: public.fn_input_governance_curator_materialize_v1 (OID 68598), public.fn_input_governance_execute (OID 68668), and public.fn_input_governance_validator_validate_v1 (OID 68599). Their wrapper bodies delegate without an independent identity predicate. Safety depends on downstream guards and the permitted caller context.

AU4. Q11–Q12 identify public.fn_input_governance_validator_handoff_assert_v1 (OID 241753) as a SECURITY INVOKER delegation to programacion.fn_input_governance_validator_handoff_assert_v1 (OID 238083). The observed service_role grants permit the public call but not direct internal callability. Successful execution and its authorization behavior remain untested.

AU5. Q12's internal Curator (OID 68873) contains strategy, run, assessment, graph-count, freshness-count and receipt-verification conditions with exception paths. These are CURRENT implemented guards, not proofs of historical presence or runtime effectiveness.

AU6. Q12's handoff receipt creator (OID 237817) checks Curator identity, run status, Validator non-invocation and the 47-family universe, and constructs a digest-bound handoff subject. The Validator handoff assertion (OID 238083) reconstructs the subject and checks the persisted receipt.

AU7. Q12's Validator (OID 68877) checks continuation currentness on specified statuses and routes terminal completion through graph finalization (OID 244314). The graph finalizer checks the handoff and graph receipt on COMPLETED outcomes. Full reachable-path completeness is unproven.

AU8. Q13 failed with PostgreSQL 42883, yielding no evidence. Q14 independently verifies both authorized historical EKB row SHA-256 values against the packet.

AU9. Historical EKB IG-M107-CP2-READ-ROLE-CURRENTNESS-001 documents a prior unauthorized read (42501) and the unsuitability of a latest-13 sample as an as-of cohort substitute. The specified mitigation is query correction and authorized historical evidence reuse, not privilege escalation.

AU10. Historical EKB IG-M107-SOAK-CRITERION-DRIFT-001 records the historical soak requirements: 13/13 screens, 47/47 families, at least two eligible as-of observations per unit, zero false PASS, and zero D4 divergence. Its claim about receipt 38 is not independently recertified here.

Causal model

Two distinct failure mechanisms must remain separate: a measurement or certification query can lack read authority or sample the wrong epoch; a callable privileged wrapper can potentially omit an intended authorization gate. The first is historically documented. The second is an unproven CURRENT risk requiring verified entrypoint, identity and guard evidence.

Falsifiers

A properly authorized, historical as-of cohort with the prescribed criteria would falsify a claim that current sampling is necessary for historical certification. Successful guarded calls under explicitly authorized principals and rejected unauthorized cases would reduce wrapper-bypass concerns. A demonstrated reachable path bypassing a required guard would instead establish a concrete defect.

Constraints and unresolved

Preserve existing grants and role boundaries; avoid runtime invocations and privilege changes. P0 ACLs, effective application-identity binding, role inheritance, dynamic/remote paths, complete downstream guard proofs and negative execution results remain unknown.

Disposition: NEEDS_MORE_EVIDENCE for any CURRENT authority repair. Do not elevate permissions to make diagnostic queries succeed.

===ROLE_REPORT:AUTHORITY END===
