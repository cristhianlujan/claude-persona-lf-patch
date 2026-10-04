# CAUSAL_EFFECT_LINEAGE

Transversal LF capability for explicit causal continuity across sync/async boundaries.

- Owner: `SUPER_ADMIN`.
- States: `LINKED`, `UNLINKED`, `AMBIGUOUS`.
- Strong evidence required: scoped/opaque parent identity, scoped/opaque correlation identity, provenance, currentness, verified producer receipt, verified receiver-effect receipt, and exact receiver readback.
- `name`, object similarity and timestamp proximity are never sufficient causal evidence.
- Raw PII keys are rejected.
- The provider has no business-decision or execution authority.
- Canonical receipt/evidence dependencies remain `EVIDENCE_LEDGER` and `TYPED_EVIDENCE_REGISTRY`; this capability does not create a shadow ledger.
- IG is a consumer through N-17 binding metadata; this package does not execute N-17.
- A second non-IG async proof uses the same provider contract and requires receiver readback.
- Repository-bound only: no IG runtime cutover and no production activation.
