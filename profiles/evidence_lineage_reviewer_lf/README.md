# Evidence Lineage Reviewer LF

Read-only candidate profile for verifying LF operational claims across GitHub, Supabase, CI and EKB.

It is intentionally narrower than general audit profiles: it does not audit product quality or implement fixes. It validates evidence lineage, authority precedence, exact-revision binding and structural-identifier reconciliation.

## Governance status

- document status: `CANDIDATO`
- operation: `CREACION_PERFIL_LF`
- operational status: `READ_ONLY`
- runtime: `NO_HABILITADO`
- automatic impact: `BLOQUEADO`
- production authorization: `false`

The profile may be created and structurally validated as a candidate, but creation does not imply runtime activation, automatic promotion, production authorization, or independent-auditor status.

## Canary evidence rule

Canary closure requires exact-head CI on the real pull-request diff, merge/readback evidence and governed EKB traceability. Reconciliation with a moving `main` must preserve concurrent work and must not broaden this profile's authority or receipt scope.
