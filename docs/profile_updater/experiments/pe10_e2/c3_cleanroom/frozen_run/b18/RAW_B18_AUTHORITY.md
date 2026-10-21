===ROLE_REPORT:AUTHORITY BEGIN===

Scope: CURRENT effective function privileges, schema privileges, role memberships, SECURITY DEFINER boundaries, view access, relation privileges, and row-level security.

Evidence: QUERY_RESULT Q15R, Q16–Q24. QUERY_ERROR Q15 is retained as a query-construction failure and supplies no authorization evidence.

Function grant census: Among 14 selected functions, three have PUBLIC EXECUTE but none has a complete unrestricted PUBLIC function-and-schema grant path.

Effective role/function census: Q16 tested 140 combinations across ten roles and fourteen functions. Ten combinations have both effective schema USAGE and function EXECUTE. The positive pairs are individually preserved in Q16; the remaining pairs are negative for direct invocation under the tested role identities.

Application entry points: authenticated can directly invoke two lf_ops contract functions. service_role can directly invoke three examined public governance wrappers. Five programacion functional roles can directly invoke the examined semantic probe.

Schema trust: None of the ten examined non-owner roles has CREATE on the six tested schemas. The selected privileged functions have configured search paths, but complete name-resolution safety remains unproven.

Privileged helper: programacion.fn_input_effective_rule_links_v1(integer,text), OID 142747, is owned by postgres and marked SECURITY DEFINER. Authenticated and service roles have EXECUTE on the function but lack USAGE on programacion.

View access: lf_ops.v_b2b_backoffice_login_contract, OID 49429, has a catalog-confirmed dependency on function OID 49427. Neither authenticated nor service_role has an effective direct SELECT path to this view.

Relation access: All 26 inspected lf_ops and lf_design relations are owned by postgres, have RLS enabled without FORCE RLS, and lack direct authenticated SELECT. All 26 carry the deny_direct_client_access policy for anon and authenticated, with both policy expressions set to false.

Material authority hypothesis: Two authenticated-callable SECURITY INVOKER contract functions directly reference tables unavailable to the authenticated role. This is a source-and-catalog-supported functional-access concern, not a demonstrated executed failure.

Negative falsifiers: No unrestricted PUBLIC function/schema path was found among the selected functions. No authenticated direct access to the 26 examined relations was found. No authenticated direct SELECT on the identified view was found. No unauthorized data disclosure or privilege escalation was demonstrated.

Constraints: Preserve least privilege, explicit owner boundaries, client-data restrictions, RLS, and the distinction between authorized wrapper invocation and internal function EXECUTE.

Unresolved: Intended contract-function caller identity; actual authenticated invocation outcome; role context inside nested queries; untested consumers and grants; complete function-resolution safety; and whether the callable-but-unusable interface is an actual supported-use defect.

Decision: MEASURE_FIRST. Do not broaden grants, disable RLS, or convert contract functions to SECURITY DEFINER without a demonstrated contract-specific need and independent security review.

Costs: NO_MEDIDO.

Blindness limitation: Strict role independence cannot be independently attested in this shared conversation.

===ROLE_REPORT:AUTHORITY END===
